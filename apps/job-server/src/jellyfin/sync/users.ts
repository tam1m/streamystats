import { eq } from "drizzle-orm";
import { db, users, Server, NewUser } from "@streamystats/database";
import { JellyfinClient, JellyfinUser } from "../client";
import {
  SyncMetricsTracker,
  SyncResult,
  createSyncResult,
} from "../sync-metrics";
import pMap from "p-map";

export interface UserSyncOptions {
  batchSize?: number;
  concurrency?: number;
}

export interface UserSyncData {
  usersProcessed: number;
  usersInserted: number;
  usersUpdated: number;
}

export async function syncUsers(
  server: Server,
  options: UserSyncOptions = {}
): Promise<SyncResult<UserSyncData>> {
  const { batchSize = 100, concurrency = 5 } = options;

  const metrics = new SyncMetricsTracker();
  const client = JellyfinClient.fromServer(server);
  const errors: string[] = [];

  try {
    console.log(`Starting user sync for server ${server.name}`);

    // Fetch users from Jellyfin
    metrics.incrementApiRequests();
    const jellyfinUsers = await client.getUsers();
    console.log(`Fetched ${jellyfinUsers.length} users from Jellyfin`);

    // Process users in batches with controlled concurrency
    let usersInserted = 0;
    let usersUpdated = 0;

    await pMap(
      jellyfinUsers,
      async (jellyfinUser) => {
        try {
          await processUser(jellyfinUser, server.id, metrics);

          // Check if this was an insert or update by checking if user existed
          const existingUser = await db
            .select()
            .from(users)
            .where(eq(users.id, jellyfinUser.Id))
            .limit(1);

          if (existingUser.length === 0) {
            usersInserted++;
            metrics.incrementUsersInserted();
          } else {
            usersUpdated++;
            metrics.incrementUsersUpdated();
          }

          metrics.incrementUsersProcessed();
        } catch (error) {
          console.error(`Error processing user ${jellyfinUser.Id}:`, error);
          metrics.incrementErrors();
          errors.push(
            `User ${jellyfinUser.Id}: ${
              error instanceof Error ? error.message : "Unknown error"
            }`
          );
        }
      },
      { concurrency }
    );

    const finalMetrics = metrics.finish();
    const data: UserSyncData = {
      usersProcessed: finalMetrics.usersProcessed,
      usersInserted: finalMetrics.usersInserted,
      usersUpdated: finalMetrics.usersUpdated,
    };

    console.log(`User sync completed for server ${server.name}:`, data);

    if (errors.length > 0) {
      return createSyncResult("partial", data, finalMetrics, undefined, errors);
    }

    return createSyncResult("success", data, finalMetrics);
  } catch (error) {
    console.error(`User sync failed for server ${server.name}:`, error);
    const finalMetrics = metrics.finish();
    const errorData: UserSyncData = {
      usersProcessed: finalMetrics.usersProcessed,
      usersInserted: finalMetrics.usersInserted,
      usersUpdated: finalMetrics.usersUpdated,
    };
    return createSyncResult(
      "error",
      errorData,
      finalMetrics,
      error instanceof Error ? error.message : "Unknown error"
    );
  }
}

async function processUser(
  jellyfinUser: JellyfinUser,
  serverId: number,
  metrics: SyncMetricsTracker
): Promise<void> {
  const userData: NewUser = {
    id: jellyfinUser.Id,
    name: jellyfinUser.Name,
    serverId,
    lastLoginDate: jellyfinUser.LastLoginDate
      ? new Date(jellyfinUser.LastLoginDate)
      : null,
    lastActivityDate: jellyfinUser.LastActivityDate
      ? new Date(jellyfinUser.LastActivityDate)
      : null,
    hasPassword: jellyfinUser.HasPassword,
    hasConfiguredPassword: jellyfinUser.HasConfiguredPassword,
    hasConfiguredEasyPassword: jellyfinUser.HasConfiguredEasyPassword,
    enableAutoLogin: jellyfinUser.EnableAutoLogin,
    isAdministrator: jellyfinUser.IsAdministrator,
    isHidden: jellyfinUser.IsHidden,
    isDisabled: jellyfinUser.IsDisabled,
    enableUserPreferenceAccess: jellyfinUser.EnableUserPreferenceAccess,
    enableRemoteControlOfOtherUsers:
      jellyfinUser.EnableRemoteControlOfOtherUsers,
    enableSharedDeviceControl: jellyfinUser.EnableSharedDeviceControl,
    enableRemoteAccess: jellyfinUser.EnableRemoteAccess,
    enableLiveTvManagement: jellyfinUser.EnableLiveTvManagement,
    enableLiveTvAccess: jellyfinUser.EnableLiveTvAccess,
    enableMediaPlayback: jellyfinUser.EnableMediaPlayback,
    enableAudioPlaybackTranscoding: jellyfinUser.EnableAudioPlaybackTranscoding,
    enableVideoPlaybackTranscoding: jellyfinUser.EnableVideoPlaybackTranscoding,
    enablePlaybackRemuxing: jellyfinUser.EnablePlaybackRemuxing,
    enableContentDeletion: jellyfinUser.EnableContentDeletion,
    enableContentDownloading: jellyfinUser.EnableContentDownloading,
    enableSyncTranscoding: jellyfinUser.EnableSyncTranscoding,
    enableMediaConversion: jellyfinUser.EnableMediaConversion,
    enableAllDevices: jellyfinUser.EnableAllDevices,
    enableAllChannels: jellyfinUser.EnableAllChannels,
    enableAllFolders: jellyfinUser.EnableAllFolders,
    enablePublicSharing: jellyfinUser.EnablePublicSharing,
    invalidLoginAttemptCount: jellyfinUser.InvalidLoginAttemptCount,
    loginAttemptsBeforeLockout: jellyfinUser.LoginAttemptsBeforeLockout,
    maxActiveSessions: jellyfinUser.MaxActiveSessions,
    remoteClientBitrateLimit: jellyfinUser.RemoteClientBitrateLimit,
    authenticationProviderId: jellyfinUser.AuthenticationProviderId,
    passwordResetProviderId: jellyfinUser.PasswordResetProviderId,
    syncPlayAccess: jellyfinUser.SyncPlayAccess,
    updatedAt: new Date(),
  };

  // Upsert user (insert or update if exists)
  await db
    .insert(users)
    .values(userData)
    .onConflictDoUpdate({
      target: users.id,
      set: {
        ...userData,
        updatedAt: new Date(),
      },
    });

  metrics.incrementDatabaseOperations();
}
