import { SyncOptions } from "./sync";
export interface JellyfinSyncJobData {
    serverId: number;
    syncType: "full" | "users" | "libraries" | "items" | "activities" | "recent_items" | "recent_activities";
    options?: SyncOptions;
}
export interface JellyfinServerSyncJobData {
    serverId: number;
    options?: SyncOptions;
}
/**
 * Main Jellyfin sync job worker
 */
export declare function jellyfinSyncWorker(job: {
    data: JellyfinSyncJobData;
}): Promise<any>;
/**
 * Full sync job worker - performs complete sync of all data
 */
export declare function jellyfinFullSyncWorker(job: {
    data: JellyfinServerSyncJobData;
}): Promise<any>;
/**
 * Users sync job worker
 */
export declare function jellyfinUsersSyncWorker(job: {
    data: JellyfinServerSyncJobData;
}): Promise<any>;
/**
 * Libraries sync job worker
 */
export declare function jellyfinLibrariesSyncWorker(job: {
    data: JellyfinServerSyncJobData;
}): Promise<any>;
/**
 * Items sync job worker
 */
export declare function jellyfinItemsSyncWorker(job: {
    data: JellyfinServerSyncJobData;
}): Promise<any>;
/**
 * Activities sync job worker
 */
export declare function jellyfinActivitiesSyncWorker(job: {
    data: JellyfinServerSyncJobData;
}): Promise<any>;
/**
 * Recent items sync job worker
 */
export declare function jellyfinRecentItemsSyncWorker(job: {
    data: JellyfinServerSyncJobData;
}): Promise<any>;
/**
 * Recent activities sync job worker
 */
export declare function jellyfinRecentActivitiesSyncWorker(job: {
    data: JellyfinServerSyncJobData;
}): Promise<any>;
export declare const JELLYFIN_JOB_NAMES: {
    readonly FULL_SYNC: "jellyfin-full-sync";
    readonly USERS_SYNC: "jellyfin-users-sync";
    readonly LIBRARIES_SYNC: "jellyfin-libraries-sync";
    readonly ITEMS_SYNC: "jellyfin-items-sync";
    readonly ACTIVITIES_SYNC: "jellyfin-activities-sync";
    readonly RECENT_ITEMS_SYNC: "jellyfin-recent-items-sync";
    readonly RECENT_ACTIVITIES_SYNC: "jellyfin-recent-activities-sync";
};
//# sourceMappingURL=workers.d.ts.map