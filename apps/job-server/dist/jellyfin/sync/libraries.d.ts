import { Server } from "../../db/schema";
import { SyncResult } from "../sync-metrics";
export interface LibrarySyncOptions {
    batchSize?: number;
    concurrency?: number;
}
export interface LibrarySyncData {
    librariesProcessed: number;
    librariesInserted: number;
    librariesUpdated: number;
}
export declare function syncLibraries(server: Server, options?: LibrarySyncOptions): Promise<SyncResult<LibrarySyncData>>;
//# sourceMappingURL=libraries.d.ts.map