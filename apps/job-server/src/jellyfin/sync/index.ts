import { Server } from "@streamystats/database";
import { syncUsers, UserSyncOptions, UserSyncData } from "./users";
import {
  syncLibraries,
  LibrarySyncOptions,
  LibrarySyncData,
} from "./libraries";
import {
  syncItems,
  syncRecentlyAddedItems,
  ItemSyncOptions,
  ItemSyncData,
} from "./items";
import {
  syncActivities,
  syncRecentActivities,
  ActivitySyncOptions,
  ActivitySyncData,
} from "./activities";
import {
  SyncResult,
  SyncMetrics,
  SyncMetricsTracker,
  createSyncResult,
} from "../sync-metrics";

export interface SyncOptions {
  // Global options
  maxLibraryConcurrency?: number;
  dbBatchSize?: number;
  apiRequestDelayMs?: number;
  maxRetries?: number;
  retryInitialDelayMs?: number;
  adaptiveThrottling?: boolean;

  // Specific module options
  userOptions?: UserSyncOptions;
  libraryOptions?: LibrarySyncOptions;
  itemOptions?: ItemSyncOptions;
  activityOptions?: ActivitySyncOptions;
}

export interface FullSyncData {
  users: UserSyncData;
  libraries: LibrarySyncData;
  items: ItemSyncData;
  activities: ActivitySyncData;
  totalDuration: number;
}

// Default sync options based on the Elixir configuration
export const DEFAULT_SYNC_OPTIONS: SyncOptions = {
  maxLibraryConcurrency: 2,
  dbBatchSize: 1000,
  apiRequestDelayMs: 100,
  maxRetries: 3,
  retryInitialDelayMs: 1000,
  adaptiveThrottling: true,
};

/**
 * Main sync coordinator - performs a full sync of all data types
 */
export async function performFullSync(
  server: Server,
  options: SyncOptions = {}
): Promise<SyncResult<FullSyncData>> {
  const finalOptions = { ...DEFAULT_SYNC_OPTIONS, ...options };
  const globalMetrics = new SyncMetricsTracker();
  const errors: string[] = [];

  console.log(`Starting full sync for server ${server.name}`);

  try {
    // 1. Sync Users
    console.log("Step 1/4: Syncing users...");
    const usersResult = await syncUsers(server, finalOptions.userOptions);
    if (usersResult.status === "error") {
      console.error("Users sync failed:", usersResult.error);
      errors.push(`Users: ${usersResult.error}`);
    } else if (usersResult.status === "partial") {
      console.warn("Users sync completed with errors:", usersResult.errors);
      errors.push(...usersResult.errors.map((e) => `Users: ${e}`));
    }
    console.log(
      "Users sync completed:",
      usersResult.status === "error" ? "FAILED" : usersResult.data
    );

    // 2. Sync Libraries
    console.log("Step 2/4: Syncing libraries...");
    const librariesResult = await syncLibraries(
      server,
      finalOptions.libraryOptions
    );
    if (librariesResult.status === "error") {
      console.error("Libraries sync failed:", librariesResult.error);
      errors.push(`Libraries: ${librariesResult.error}`);
    } else if (librariesResult.status === "partial") {
      console.warn(
        "Libraries sync completed with errors:",
        librariesResult.errors
      );
      errors.push(...librariesResult.errors.map((e) => `Libraries: ${e}`));
    }
    console.log(
      "Libraries sync completed:",
      librariesResult.status === "error" ? "FAILED" : librariesResult.data
    );

    // 3. Sync Items (this will take the longest)
    console.log("Step 3/4: Syncing items...");
    const itemsResult = await syncItems(server, {
      ...finalOptions.itemOptions,
      maxLibraryConcurrency: finalOptions.maxLibraryConcurrency,
      apiRequestDelayMs: finalOptions.apiRequestDelayMs,
    });
    if (itemsResult.status === "error") {
      console.error("Items sync failed:", itemsResult.error);
      errors.push(`Items: ${itemsResult.error}`);
    } else if (itemsResult.status === "partial") {
      console.warn("Items sync completed with errors:", itemsResult.errors);
      errors.push(...itemsResult.errors.map((e) => `Items: ${e}`));
    }
    console.log(
      "Items sync completed:",
      itemsResult.status === "error" ? "FAILED" : itemsResult.data
    );

    // 4. Sync Activities
    console.log("Step 4/4: Syncing activities...");
    const activitiesResult = await syncActivities(
      server,
      finalOptions.activityOptions
    );
    if (activitiesResult.status === "error") {
      console.error("Activities sync failed:", activitiesResult.error);
      errors.push(`Activities: ${activitiesResult.error}`);
    } else if (activitiesResult.status === "partial") {
      console.warn(
        "Activities sync completed with errors:",
        activitiesResult.errors
      );
      errors.push(...activitiesResult.errors.map((e) => `Activities: ${e}`));
    }
    console.log(
      "Activities sync completed:",
      activitiesResult.status === "error" ? "FAILED" : activitiesResult.data
    );

    const finalMetrics = globalMetrics.finish();

    // Helper function to safely extract data from sync results
    const getSyncData = <T>(result: SyncResult<T>, defaultValue: T): T => {
      return result.status === "error" ? defaultValue : result.data;
    };

    const fullSyncData: FullSyncData = {
      users: getSyncData(usersResult, {
        usersProcessed: 0,
        usersInserted: 0,
        usersUpdated: 0,
      }),
      libraries: getSyncData(librariesResult, {
        librariesProcessed: 0,
        librariesInserted: 0,
        librariesUpdated: 0,
      }),
      items: getSyncData(itemsResult, {
        librariesProcessed: 0,
        itemsProcessed: 0,
        itemsInserted: 0,
        itemsUpdated: 0,
        itemsUnchanged: 0,
      }),
      activities: getSyncData(activitiesResult, {
        activitiesProcessed: 0,
        activitiesInserted: 0,
        activitiesUpdated: 0,
        pagesFetched: 0,
      }),
      totalDuration: finalMetrics.duration || 0,
    };

    console.log(`Full sync completed for server ${server.name}:`, {
      totalDuration: `${finalMetrics.duration || 0}ms`,
      errors: errors.length,
    });

    // Determine overall result
    const hasErrors = [
      usersResult,
      librariesResult,
      itemsResult,
      activitiesResult,
    ].some((result) => result.status === "error");

    const hasPartialErrors = [
      usersResult,
      librariesResult,
      itemsResult,
      activitiesResult,
    ].some((result) => result.status === "partial");

    if (hasErrors) {
      return createSyncResult(
        "error",
        fullSyncData,
        finalMetrics,
        "One or more sync operations failed",
        errors
      );
    } else if (hasPartialErrors || errors.length > 0) {
      return createSyncResult(
        "partial",
        fullSyncData,
        finalMetrics,
        undefined,
        errors
      );
    } else {
      return createSyncResult("success", fullSyncData, finalMetrics);
    }
  } catch (error) {
    console.error(`Full sync failed for server ${server.name}:`, error);
    const finalMetrics = globalMetrics.finish();
    const errorData: FullSyncData = {
      users: { usersProcessed: 0, usersInserted: 0, usersUpdated: 0 },
      libraries: {
        librariesProcessed: 0,
        librariesInserted: 0,
        librariesUpdated: 0,
      },
      items: {
        librariesProcessed: 0,
        itemsProcessed: 0,
        itemsInserted: 0,
        itemsUpdated: 0,
        itemsUnchanged: 0,
      },
      activities: {
        activitiesProcessed: 0,
        activitiesInserted: 0,
        activitiesUpdated: 0,
        pagesFetched: 0,
      },
      totalDuration: finalMetrics.duration || 0,
    };
    return createSyncResult(
      "error",
      errorData,
      finalMetrics,
      error instanceof Error ? error.message : "Unknown error"
    );
  }
}

// Re-export all sync functions for convenience
export {
  syncUsers,
  syncLibraries,
  syncItems,
  syncRecentlyAddedItems,
  syncActivities,
  syncRecentActivities,
};

// Re-export types
export type {
  UserSyncOptions,
  UserSyncData,
  LibrarySyncOptions,
  LibrarySyncData,
  ItemSyncOptions,
  ItemSyncData,
  ActivitySyncOptions,
  ActivitySyncData,
  SyncResult,
  SyncMetrics,
};

/**
 * Returns the default synchronization options.
 * These can be overridden by passing a map of options to the sync functions.
 */
export function getDefaultOptions(): SyncOptions {
  return { ...DEFAULT_SYNC_OPTIONS };
}
