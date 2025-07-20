import { eq, desc } from "drizzle-orm";
import {
  db,
  activities,
  Server,
  NewActivity,
  users,
} from "@streamystats/database";
import { JellyfinClient, JellyfinActivity } from "../client";
import {
  SyncMetricsTracker,
  SyncResult,
  createSyncResult,
} from "../sync-metrics";
import pMap from "p-map";

export interface ActivitySyncOptions {
  pageSize?: number;
  maxPages?: number;
  concurrency?: number;
  apiRequestDelayMs?: number;
  intelligent?: boolean; // Enable intelligent sync mode
}

export interface ActivitySyncData {
  activitiesProcessed: number;
  activitiesInserted: number;
  activitiesUpdated: number;
  pagesFetched: number;
}

const ACTIVITYLOG_SYSTEM_USERID = '00000000000000000000000000000000';

export async function syncActivities(
  server: Server,
  options: ActivitySyncOptions = {}
): Promise<SyncResult<ActivitySyncData>> {
  const {
    pageSize = 100,
    maxPages = 1000, // Prevent infinite loops
    concurrency = 5,
    apiRequestDelayMs = 100,
  } = options;

  const metrics = new SyncMetricsTracker();
  const client = JellyfinClient.fromServer(server);
  const errors: string[] = [];

  try {
    console.log(`Starting activities sync for server ${server.name}`);

    let startIndex = 0;
    let pagesFetched = 0;
    let hasMoreActivities = true;

    while (hasMoreActivities && pagesFetched < maxPages) {
      // Add delay between API requests
      if (pagesFetched > 0) {
        await new Promise((resolve) => setTimeout(resolve, apiRequestDelayMs));
      }

      try {
        metrics.incrementApiRequests();
        const jellyfinActivities = await client.getActivities(
          startIndex,
          pageSize
        );

        if (jellyfinActivities.length === 0) {
          hasMoreActivities = false;
          break;
        }

        // Process activities with controlled concurrency
        await pMap(
          jellyfinActivities,
          async (jellyfinActivity) => {
            try {
              await processActivity(jellyfinActivity, server.id, metrics);
            } catch (error) {
              console.error(
                `Error processing activity ${jellyfinActivity.Id}:`,
                error
              );
              metrics.incrementErrors();
              errors.push(
                `Activity ${jellyfinActivity.Id}: ${
                  error instanceof Error ? error.message : "Unknown error"
                }`
              );
            }
          },
          { concurrency }
        );

        startIndex += jellyfinActivities.length;
        pagesFetched++;

        // Stop if we got fewer activities than requested (indicates end of data)
        if (jellyfinActivities.length < pageSize) {
          hasMoreActivities = false;
        }
      } catch (error) {
        console.error(
          `Error fetching activities page ${pagesFetched + 1}:`,
          error
        );
        metrics.incrementErrors();
        errors.push(
          `Page ${pagesFetched + 1}: ${
            error instanceof Error ? error.message : "Unknown error"
          }`
        );
        break; // Stop processing on API error
      }
    }

    const finalMetrics = metrics.finish();
    const data: ActivitySyncData = {
      activitiesProcessed: finalMetrics.activitiesProcessed,
      activitiesInserted: finalMetrics.activitiesInserted,
      activitiesUpdated: finalMetrics.activitiesUpdated,
      pagesFetched,
    };

    console.log(`Activities sync completed for server ${server.name}:`, data);

    if (errors.length > 0) {
      return createSyncResult("partial", data, finalMetrics, undefined, errors);
    }

    return createSyncResult("success", data, finalMetrics);
  } catch (error) {
    console.error(`Activities sync failed for server ${server.name}:`, error);
    const finalMetrics = metrics.finish();
    const errorData: ActivitySyncData = {
      activitiesProcessed: finalMetrics.activitiesProcessed,
      activitiesInserted: finalMetrics.activitiesInserted,
      activitiesUpdated: finalMetrics.activitiesUpdated,
      pagesFetched: 0,
    };
    return createSyncResult(
      "error",
      errorData,
      finalMetrics,
      error instanceof Error ? error.message : "Unknown error"
    );
  }
}

export async function syncRecentActivities(
  server: Server,
  options: ActivitySyncOptions = {}
): Promise<SyncResult<ActivitySyncData>> {
  const {
    pageSize = 100,
    maxPages = 10,
    concurrency = 5,
    apiRequestDelayMs = 100,
    intelligent = false,
  } = options;

  const metrics = new SyncMetricsTracker();
  const client = JellyfinClient.fromServer(server);
  const errors: string[] = [];

  try {
    console.log(
      `Starting recent activities sync for server ${server.name} (intelligent: ${intelligent})`
    );

    let mostRecentDbActivityId: string | null = null;
    let foundLastKnownActivity = false;

    if (intelligent) {
      // Get the most recent activity ID from our database
      const lastActivity = await db
        .select({ id: activities.id, date: activities.date })
        .from(activities)
        .where(eq(activities.serverId, server.id))
        .orderBy(desc(activities.date))
        .limit(1);

      if (lastActivity.length > 0) {
        mostRecentDbActivityId = lastActivity[0].id;
        console.log(
          `Most recent activity in DB: ${mostRecentDbActivityId} (${lastActivity[0].date})`
        );
      } else {
        console.log(
          "No activities found in database, performing full recent sync"
        );
      }
    }

    let startIndex = 0;
    let pagesFetched = 0;
    let activitiesProcessed = 0;

    while (pagesFetched < maxPages) {
      // Add delay between API requests
      if (pagesFetched > 0) {
        await new Promise((resolve) => setTimeout(resolve, apiRequestDelayMs));
      }

      try {
        metrics.incrementApiRequests();
        const jellyfinActivities = await client.getActivities(
          startIndex,
          pageSize
        );

        if (jellyfinActivities.length === 0) {
          console.log("No more activities to fetch");
          break;
        }

        // In intelligent mode, check if we've found our last known activity
        if (intelligent && mostRecentDbActivityId) {
          const foundIndex = jellyfinActivities.findIndex(
            (activity) => activity.Id === mostRecentDbActivityId
          );

          if (foundIndex >= 0) {
            console.log(
              `Found last known activity at index ${foundIndex}, stopping intelligent sync`
            );
            // Only process activities before the found index (newer activities)
            const newActivities = jellyfinActivities.slice(0, foundIndex);
            if (newActivities.length > 0) {
              await pMap(
                newActivities,
                async (jellyfinActivity) => {
                  try {
                    await processActivity(jellyfinActivity, server.id, metrics);
                    activitiesProcessed++;
                  } catch (error) {
                    console.error(
                      `Error processing recent activity ${jellyfinActivity.Id}:`,
                      error
                    );
                    metrics.incrementErrors();
                    errors.push(
                      `Activity ${jellyfinActivity.Id}: ${
                        error instanceof Error ? error.message : "Unknown error"
                      }`
                    );
                  }
                },
                { concurrency }
              );
            }
            foundLastKnownActivity = true;
            break;
          }
        }

        // Process all activities in the current page
        await pMap(
          jellyfinActivities,
          async (jellyfinActivity) => {
            try {
              await processActivity(jellyfinActivity, server.id, metrics);
              activitiesProcessed++;
            } catch (error) {
              console.error(
                `Error processing recent activity ${jellyfinActivity.Id}:`,
                error
              );
              metrics.incrementErrors();
              errors.push(
                `Activity ${jellyfinActivity.Id}: ${
                  error instanceof Error ? error.message : "Unknown error"
                }`
              );
            }
          },
          { concurrency }
        );

        startIndex += jellyfinActivities.length;
        pagesFetched++;

        // In intelligent mode, if we haven't found the last known activity yet,
        // but we've processed a reasonable amount, stop to prevent infinite loops
        if (
          intelligent &&
          !foundLastKnownActivity &&
          activitiesProcessed >= pageSize * 3
        ) {
          console.log(
            `Intelligent sync processed ${activitiesProcessed} activities without finding last known activity, stopping`
          );
          break;
        }

        // Stop if we got fewer activities than requested (indicates end of data)
        if (jellyfinActivities.length < pageSize) {
          console.log("Reached end of available activities");
          break;
        }
      } catch (error) {
        console.error(
          `Error fetching activities page ${pagesFetched + 1}:`,
          error
        );
        metrics.incrementErrors();
        errors.push(
          `Page ${pagesFetched + 1}: ${
            error instanceof Error ? error.message : "Unknown error"
          }`
        );
        break; // Stop processing on API error
      }
    }

    const finalMetrics = metrics.finish();
    const data: ActivitySyncData = {
      activitiesProcessed: finalMetrics.activitiesProcessed,
      activitiesInserted: finalMetrics.activitiesInserted,
      activitiesUpdated: finalMetrics.activitiesUpdated,
      pagesFetched,
    };

    const syncType = intelligent ? "intelligent recent" : "recent";
    console.log(
      `${syncType} activities sync completed for server ${server.name}:`,
      data
    );

    if (intelligent && mostRecentDbActivityId && !foundLastKnownActivity) {
      console.log(
        `Warning: Intelligent sync did not find the last known activity (${mostRecentDbActivityId}). ` +
          `This might indicate the activity is older than the sync window.`
      );
    }

    if (errors.length > 0) {
      return createSyncResult("partial", data, finalMetrics, undefined, errors);
    }

    return createSyncResult("success", data, finalMetrics);
  } catch (error) {
    console.error(
      `Recent activities sync failed for server ${server.name}:`,
      error
    );
    const finalMetrics = metrics.finish();
    const errorData: ActivitySyncData = {
      activitiesProcessed: finalMetrics.activitiesProcessed,
      activitiesInserted: finalMetrics.activitiesInserted,
      activitiesUpdated: finalMetrics.activitiesUpdated,
      pagesFetched: 0,
    };
    return createSyncResult(
      "error",
      errorData,
      finalMetrics,
      error instanceof Error ? error.message : "Unknown error"
    );
  }
}

async function processActivity(
  jellyfinActivity: JellyfinActivity,
  serverId: number,
  metrics: SyncMetricsTracker
): Promise<void> {
  // Check if activity already exists
  const existingActivity = await db
    .select()
    .from(activities)
    .where(eq(activities.id, jellyfinActivity.Id))
    .limit(1);

  const isNewActivity = existingActivity.length === 0;

  // Validate userId - check if user exists in our database
  let validUserId: string | null = null;
  if (jellyfinActivity.UserId) {
    try {
      const userExists = await db
        .select({ id: users.id })
        .from(users)
        .where(eq(users.id, jellyfinActivity.UserId))
        .limit(1);

      if (userExists.length > 0) {
        validUserId = jellyfinActivity.UserId;
      } else if (jellyfinActivity.UserId == ACTIVITYLOG_SYSTEM_USERID) {
        // this is a system event (plugin install/uninstall, ...) we do not print a warning
      } else {
        console.warn(
          `Activity ${jellyfinActivity.Id} references non-existent user ${jellyfinActivity.UserId}, setting to null`
        );
      }
    } catch (error) {
      console.warn(
        `Error checking user existence for activity ${jellyfinActivity.Id}: ${error}. Setting userId to null.`
      );
    }
  }

  const activityData: NewActivity = {
    id: jellyfinActivity.Id,
    name: jellyfinActivity.Name,
    shortOverview: jellyfinActivity.ShortOverview || null,
    type: jellyfinActivity.Type,
    date: new Date(jellyfinActivity.Date),
    severity: jellyfinActivity.Severity,
    serverId,
    userId: validUserId,
    itemId: jellyfinActivity.ItemId || null,
  };

  // Upsert activity (insert or update if exists)
  await db
    .insert(activities)
    .values(activityData)
    .onConflictDoUpdate({
      target: activities.id,
      set: {
        ...activityData,
      },
    });

  metrics.incrementDatabaseOperations();

  if (isNewActivity) {
    metrics.incrementActivitiesInserted();
  } else {
    metrics.incrementActivitiesUpdated();
  }

  metrics.incrementActivitiesProcessed();
}
