import { Server } from "../../db/schema";
import { SyncResult } from "../sync-metrics";
export interface UserSyncOptions {
    batchSize?: number;
    concurrency?: number;
}
export interface UserSyncData {
    usersProcessed: number;
    usersInserted: number;
    usersUpdated: number;
}
export declare function syncUsers(server: Server, options?: UserSyncOptions): Promise<SyncResult<UserSyncData>>;
//# sourceMappingURL=users.d.ts.map