"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.syncUsers = syncUsers;
exports.syncLibraries = syncLibraries;
exports.syncActivities = syncActivities;
exports.syncItems = syncItems;
const database_1 = require("@streamystats/database");
// Helper function to sync users
async function syncUsers(serverId, usersData) {
    let syncedCount = 0;
    for (const userData of usersData) {
        try {
            const newUser = {
                id: userData.Id,
                name: userData.Name,
                serverId,
                lastLoginDate: userData.LastLoginDate
                    ? new Date(userData.LastLoginDate)
                    : null,
                lastActivityDate: userData.LastActivityDate
                    ? new Date(userData.LastActivityDate)
                    : null,
                hasPassword: userData.HasPassword || false,
                hasConfiguredPassword: userData.HasConfiguredPassword || false,
                hasConfiguredEasyPassword: userData.HasConfiguredEasyPassword || false,
                enableAutoLogin: userData.Configuration?.EnableAutoLogin || false,
                isAdministrator: userData.Policy?.IsAdministrator || false,
                isHidden: userData.Policy?.IsHidden || false,
                isDisabled: userData.Policy?.IsDisabled || false,
                enableUserPreferenceAccess: userData.Policy?.EnableUserPreferenceAccess !== false,
                enableRemoteControlOfOtherUsers: userData.Policy?.EnableRemoteControlOfOtherUsers || false,
                enableSharedDeviceControl: userData.Policy?.EnableSharedDeviceControl || false,
                enableRemoteAccess: userData.Policy?.EnableRemoteAccess !== false,
                enableLiveTvManagement: userData.Policy?.EnableLiveTvManagement || false,
                enableLiveTvAccess: userData.Policy?.EnableLiveTvAccess !== false,
                enableMediaPlayback: userData.Policy?.EnableMediaPlayback !== false,
                enableAudioPlaybackTranscoding: userData.Policy?.EnableAudioPlaybackTranscoding !== false,
                enableVideoPlaybackTranscoding: userData.Policy?.EnableVideoPlaybackTranscoding !== false,
                enablePlaybackRemuxing: userData.Policy?.EnablePlaybackRemuxing !== false,
                enableContentDeletion: userData.Policy?.EnableContentDeletion || false,
                enableContentDownloading: userData.Policy?.EnableContentDownloading || false,
                enableSyncTranscoding: userData.Policy?.EnableSyncTranscoding !== false,
                enableMediaConversion: userData.Policy?.EnableMediaConversion || false,
                enableAllDevices: userData.Policy?.EnableAllDevices !== false,
                enableAllChannels: userData.Policy?.EnableAllChannels !== false,
                enableAllFolders: userData.Policy?.EnableAllFolders !== false,
                enablePublicSharing: userData.Policy?.EnablePublicSharing || false,
                invalidLoginAttemptCount: userData.Policy?.InvalidLoginAttemptCount || 0,
                loginAttemptsBeforeLockout: userData.Policy?.LoginAttemptsBeforeLockout || 3,
                maxActiveSessions: userData.Policy?.MaxActiveSessions || 0,
                remoteClientBitrateLimit: userData.Policy?.RemoteClientBitrateLimit || 0,
                authenticationProviderId: userData.Policy?.AuthenticationProviderId ||
                    "Jellyfin.Server.Implementations.Users.DefaultAuthenticationProvider",
                passwordResetProviderId: userData.Policy?.PasswordResetProviderId ||
                    "Jellyfin.Server.Implementations.Users.DefaultPasswordResetProvider",
                syncPlayAccess: userData.Policy?.SyncPlayAccess || "CreateAndJoinGroups",
            };
            await database_1.db.insert(database_1.users).values(newUser).onConflictDoUpdate({
                target: database_1.users.id,
                set: newUser,
            });
            syncedCount++;
        }
        catch (error) {
            console.error(`Error syncing user ${userData.Id}:`, error);
        }
    }
    return syncedCount;
}
// Helper function to sync libraries
async function syncLibraries(serverId, librariesData) {
    let syncedCount = 0;
    for (const libraryData of librariesData) {
        try {
            const newLibrary = {
                id: libraryData.ItemId,
                name: libraryData.Name,
                type: libraryData.CollectionType || "mixed",
                serverId,
            };
            await database_1.db.insert(database_1.libraries).values(newLibrary).onConflictDoUpdate({
                target: database_1.libraries.id,
                set: newLibrary,
            });
            syncedCount++;
        }
        catch (error) {
            console.error(`Error syncing library ${libraryData.ItemId}:`, error);
        }
    }
    return syncedCount;
}
// Helper function to sync activities
async function syncActivities(serverId, activitiesData) {
    let syncedCount = 0;
    for (const activityData of activitiesData) {
        try {
            const newActivity = {
                id: activityData.Id.toString(),
                name: activityData.Name,
                shortOverview: activityData.ShortOverview,
                type: activityData.Type,
                date: new Date(activityData.Date),
                severity: activityData.Severity,
                serverId,
                userId: activityData.UserId || null,
                itemId: activityData.ItemId || null,
            };
            await database_1.db.insert(database_1.activities).values(newActivity).onConflictDoUpdate({
                target: database_1.activities.id,
                set: newActivity,
            });
            syncedCount++;
        }
        catch (error) {
            console.error(`Error syncing activity ${activityData.Id}:`, error);
        }
    }
    return syncedCount;
}
// Helper function to sync items
async function syncItems(serverId, libraryId, itemsData) {
    let syncedCount = 0;
    for (const itemData of itemsData) {
        try {
            const newItem = {
                id: itemData.Id,
                serverId,
                libraryId,
                name: itemData.Name || "",
                type: itemData.Type || "",
                originalTitle: itemData.OriginalTitle,
                etag: itemData.Etag,
                dateCreated: itemData.DateCreated
                    ? new Date(itemData.DateCreated)
                    : null,
                container: itemData.Container,
                sortName: itemData.SortName,
                premiereDate: itemData.PremiereDate
                    ? new Date(itemData.PremiereDate)
                    : null,
                path: itemData.Path,
                officialRating: itemData.OfficialRating,
                overview: itemData.Overview,
                communityRating: itemData.CommunityRating,
                runtimeTicks: itemData.RunTimeTicks || 0,
                productionYear: itemData.ProductionYear,
                isFolder: itemData.IsFolder || false,
                parentId: itemData.ParentId,
                mediaType: itemData.MediaType,
                width: itemData.Width,
                height: itemData.Height,
                seriesName: itemData.SeriesName,
                seriesId: itemData.SeriesId,
                seasonId: itemData.SeasonId,
                seasonName: itemData.SeasonName,
                indexNumber: itemData.IndexNumber,
                parentIndexNumber: itemData.ParentIndexNumber,
                videoType: itemData.VideoType,
                hasSubtitles: itemData.HasSubtitles || false,
                channelId: itemData.ChannelId,
                locationType: itemData.LocationType,
                genres: itemData.Genres || null,
                primaryImageAspectRatio: itemData.PrimaryImageAspectRatio,
                primaryImageTag: itemData.ImageTags?.Primary,
                seriesPrimaryImageTag: itemData.SeriesPrimaryImageTag,
                primaryImageThumbTag: itemData.ImageTags?.Thumb,
                primaryImageLogoTag: itemData.ImageTags?.Logo,
                rawData: itemData,
            };
            await database_1.db.insert(database_1.items).values(newItem).onConflictDoUpdate({
                target: database_1.items.id,
                set: newItem,
            });
            syncedCount++;
        }
        catch (error) {
            console.error(`Error syncing item ${itemData.Id}:`, error);
        }
    }
    return syncedCount;
}
