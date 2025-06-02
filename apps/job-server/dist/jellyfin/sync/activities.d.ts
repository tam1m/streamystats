import { Server } from "../../db/schema";
import { SyncResult } from "../sync-metrics";
export interface ActivitySyncOptions {
    pageSize?: number;
    maxPages?: number;
    concurrency?: number;
    apiRequestDelayMs?: number;
    intelligent?: boolean;
}
export interface ActivitySyncData {
    activitiesProcessed: number;
    activitiesInserted: number;
    activitiesUpdated: number;
    pagesFetched: number;
}
export declare function syncActivities(server: Server, options?: ActivitySyncOptions): Promise<SyncResult<ActivitySyncData>>;
export declare function syncRecentActivities(server: Server, options?: ActivitySyncOptions): Promise<SyncResult<ActivitySyncData>>;
//# sourceMappingURL=activities.d.ts.map