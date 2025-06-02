import PgBoss from "pg-boss";
export declare function initializeJobQueue(): Promise<PgBoss>;
export declare function getJobQueue(): Promise<PgBoss>;
export declare function stopJobQueue(): Promise<void>;
export declare const JobTypes: {
    readonly FETCH_EXTERNAL_DATA: "fetch-external-data";
    readonly GENERATE_EMBEDDINGS: "generate-embeddings";
    readonly BATCH_PROCESS_POSTS: "batch-process-posts";
    readonly CUSTOM_PROCESSING: "custom-processing";
    readonly SYNC_SERVER_DATA: "sync-server-data";
    readonly ADD_SERVER: "add-server";
    readonly GENERATE_MEDIA_EMBEDDINGS: "generate-media-embeddings";
    readonly SEQUENTIAL_SERVER_SYNC: "sequential-server-sync";
};
export type JobType = (typeof JobTypes)[keyof typeof JobTypes];
//# sourceMappingURL=queue.d.ts.map