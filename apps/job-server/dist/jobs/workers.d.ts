import { jellyfinSyncWorker, jellyfinFullSyncWorker, jellyfinUsersSyncWorker, jellyfinLibrariesSyncWorker, jellyfinItemsSyncWorker, jellyfinActivitiesSyncWorker, jellyfinRecentItemsSyncWorker, jellyfinRecentActivitiesSyncWorker, JELLYFIN_JOB_NAMES } from "../jellyfin/workers";
export declare function syncServerDataJob(job: any): Promise<{
    success: boolean;
    syncedCount: number;
    endpoint: any;
}>;
export declare function addServerJob(job: any): Promise<{
    success: boolean;
    server: {
        id: number;
        name: string;
        url: string;
        apiKey: string;
        lastSyncedPlaybackId: number;
        localAddress: string | null;
        serverName: string | null;
        version: string | null;
        productName: string | null;
        operatingSystem: string | null;
        startupWizardCompleted: boolean;
        openAiApiToken: string | null;
        autoGenerateEmbeddings: boolean;
        ollamaApiToken: string | null;
        ollamaBaseUrl: string | null;
        ollamaModel: string | null;
        embeddingProvider: string | null;
        syncStatus: string;
        syncProgress: string;
        syncError: string | null;
        lastSyncStarted: Date | null;
        lastSyncCompleted: Date | null;
        createdAt: Date;
        updatedAt: Date;
    };
}>;
export declare function generateMediaEmbeddingsJob(job: any): Promise<{
    success: boolean;
    processedCount: number;
    itemType: any;
}>;
export declare function fetchExternalDataJob(job: any): Promise<{
    success: boolean;
    data: {
        id: number;
        createdAt: Date;
        updatedAt: Date;
        externalId: string | null;
        title: string;
        content: string | null;
        author: string | null;
        metadata: unknown;
        embedding: unknown;
        processed: boolean | null;
    };
}>;
export declare function generateEmbeddingsJob(job: any): Promise<{
    success: boolean;
    data: {
        id: number;
        createdAt: Date;
        updatedAt: Date;
        externalId: string | null;
        title: string;
        content: string | null;
        author: string | null;
        metadata: unknown;
        embedding: unknown;
        processed: boolean | null;
    };
}>;
export declare function batchProcessPostsJob(job: any): Promise<{
    success: boolean;
    processedCount: number;
    data: {
        id: number;
        createdAt: Date;
        updatedAt: Date;
        externalId: string | null;
        title: string;
        content: string | null;
        author: string | null;
        metadata: unknown;
        embedding: unknown;
        processed: boolean | null;
    }[];
}>;
export declare function customProcessingJob(job: any): Promise<{
    success: boolean;
    data: {
        message: string;
        action: any;
    };
}>;
export declare function sequentialServerSyncJob(job: any): Promise<{
    success: boolean;
    syncResults: {
        users: number;
        libraries: number;
        items: number;
        activities: number;
    };
}>;
export { jellyfinSyncWorker, jellyfinFullSyncWorker, jellyfinUsersSyncWorker, jellyfinLibrariesSyncWorker, jellyfinItemsSyncWorker, jellyfinActivitiesSyncWorker, jellyfinRecentItemsSyncWorker, jellyfinRecentActivitiesSyncWorker, JELLYFIN_JOB_NAMES, };
//# sourceMappingURL=workers.d.ts.map