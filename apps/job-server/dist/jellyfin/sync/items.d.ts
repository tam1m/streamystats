import { Server } from "../../db/schema";
import { SyncResult } from "../sync-metrics";
export interface ItemSyncOptions {
    itemPageSize?: number;
    batchSize?: number;
    maxLibraryConcurrency?: number;
    itemConcurrency?: number;
    apiRequestDelayMs?: number;
    recentItemsLimit?: number;
}
export interface ItemSyncData {
    librariesProcessed: number;
    itemsProcessed: number;
    itemsInserted: number;
    itemsUpdated: number;
    itemsUnchanged: number;
}
export declare function syncItems(server: Server, options?: ItemSyncOptions): Promise<SyncResult<ItemSyncData>>;
export declare function syncRecentlyAddedItems(server: Server, limit?: number): Promise<SyncResult<ItemSyncData>>;
//# sourceMappingURL=items.d.ts.map