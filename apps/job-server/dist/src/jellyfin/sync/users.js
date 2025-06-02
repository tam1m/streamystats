"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.syncUsers = syncUsers;
const drizzle_orm_1 = require("drizzle-orm");
const connection_1 = require("../../db/connection");
const schema_1 = require("../../db/schema");
const client_1 = require("../client");
const sync_metrics_1 = require("../sync-metrics");
const p_map_1 = __importDefault(require("p-map"));
async function syncUsers(server, options = {}) {
    const { batchSize = 100, concurrency = 5 } = options;
    const metrics = new sync_metrics_1.SyncMetricsTracker();
    const client = client_1.JellyfinClient.fromServer(server);
    const errors = [];
    try {
        console.log(`Starting user sync for server ${server.name}`);
        // Fetch users from Jellyfin
        metrics.incrementApiRequests();
        const jellyfinUsers = await client.getUsers();
        console.log(`Fetched ${jellyfinUsers.length} users from Jellyfin`);
        // Process users in batches with controlled concurrency
        let usersInserted = 0;
        let usersUpdated = 0;
        await (0, p_map_1.default)(jellyfinUsers, async (jellyfinUser) => {
            try {
                await processUser(jellyfinUser, server.id, metrics);
                // Check if this was an insert or update by checking if user existed
                const existingUser = await connection_1.db
                    .select()
                    .from(schema_1.users)
                    .where((0, drizzle_orm_1.eq)(schema_1.users.id, jellyfinUser.Id))
                    .limit(1);
                if (existingUser.length === 0) {
                    usersInserted++;
                    metrics.incrementUsersInserted();
                }
                else {
                    usersUpdated++;
                    metrics.incrementUsersUpdated();
                }
                metrics.incrementUsersProcessed();
            }
            catch (error) {
                console.error(`Error processing user ${jellyfinUser.Id}:`, error);
                metrics.incrementErrors();
                errors.push(`User ${jellyfinUser.Id}: ${error instanceof Error ? error.message : "Unknown error"}`);
            }
        }, { concurrency });
        const finalMetrics = metrics.finish();
        const data = {
            usersProcessed: finalMetrics.usersProcessed,
            usersInserted: finalMetrics.usersInserted,
            usersUpdated: finalMetrics.usersUpdated,
        };
        console.log(`User sync completed for server ${server.name}:`, data);
        if (errors.length > 0) {
            return (0, sync_metrics_1.createSyncResult)("partial", data, finalMetrics, undefined, errors);
        }
        return (0, sync_metrics_1.createSyncResult)("success", data, finalMetrics);
    }
    catch (error) {
        console.error(`User sync failed for server ${server.name}:`, error);
        const finalMetrics = metrics.finish();
        const errorData = {
            usersProcessed: finalMetrics.usersProcessed,
            usersInserted: finalMetrics.usersInserted,
            usersUpdated: finalMetrics.usersUpdated,
        };
        return (0, sync_metrics_1.createSyncResult)("error", errorData, finalMetrics, error instanceof Error ? error.message : "Unknown error");
    }
}
async function processUser(jellyfinUser, serverId, metrics) {
    const userData = {
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
        enableRemoteControlOfOtherUsers: jellyfinUser.EnableRemoteControlOfOtherUsers,
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
    await connection_1.db
        .insert(schema_1.users)
        .values(userData)
        .onConflictDoUpdate({
        target: schema_1.users.id,
        set: {
            ...userData,
            updatedAt: new Date(),
        },
    });
    metrics.incrementDatabaseOperations();
}
