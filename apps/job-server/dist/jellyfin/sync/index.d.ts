import { Server } from "../../db/schema";
import { syncUsers, UserSyncOptions, UserSyncData } from "./users";
import { syncLibraries, LibrarySyncOptions, LibrarySyncData } from "./libraries";
import { syncItems, syncRecentlyAddedItems, ItemSyncOptions, ItemSyncData } from "./items";
import { syncActivities, syncRecentActivities, ActivitySyncOptions, ActivitySyncData } from "./activities";
import { SyncResult, SyncMetrics } from "../sync-metrics";
export interface SyncOptions {
    maxLibraryConcurrency?: number;
    dbBatchSize?: number;
    apiRequestDelayMs?: number;
    maxRetries?: number;
    retryInitialDelayMs?: number;
    adaptiveThrottling?: boolean;
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
export declare const DEFAULT_SYNC_OPTIONS: SyncOptions;
/**
 * Main sync coordinator - performs a full sync of all data types
 */
export declare function performFullSync(server: Server, options?: SyncOptions): Promise<SyncResult<FullSyncData>>;
export { syncUsers, syncLibraries, syncItems, syncRecentlyAddedItems, syncActivities, syncRecentActivities, };
export type { UserSyncOptions, UserSyncData, LibrarySyncOptions, LibrarySyncData, ItemSyncOptions, ItemSyncData, ActivitySyncOptions, ActivitySyncData, SyncResult, SyncMetrics, };
/**
 * Returns the default synchronization options.
 * These can be overridden by passing a map of options to the sync functions.
 */
export declare function getDefaultOptions(): SyncOptions;
//# sourceMappingURL=index.d.ts.map