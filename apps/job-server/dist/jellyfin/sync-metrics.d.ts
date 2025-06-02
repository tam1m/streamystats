export interface SyncMetrics {
    apiRequests: number;
    databaseOperations: number;
    itemsProcessed: number;
    itemsInserted: number;
    itemsUpdated: number;
    itemsUnchanged: number;
    usersProcessed: number;
    usersInserted: number;
    usersUpdated: number;
    librariesProcessed: number;
    librariesInserted: number;
    librariesUpdated: number;
    activitiesProcessed: number;
    activitiesInserted: number;
    activitiesUpdated: number;
    errors: number;
    startTime: Date;
    endTime?: Date;
    duration?: number;
}
export declare class SyncMetricsTracker {
    private metrics;
    constructor();
    incrementApiRequests(count?: number): void;
    incrementDatabaseOperations(count?: number): void;
    incrementItemsProcessed(count?: number): void;
    incrementItemsInserted(count?: number): void;
    incrementItemsUpdated(count?: number): void;
    incrementItemsUnchanged(count?: number): void;
    incrementUsersProcessed(count?: number): void;
    incrementUsersInserted(count?: number): void;
    incrementUsersUpdated(count?: number): void;
    incrementLibrariesProcessed(count?: number): void;
    incrementLibrariesInserted(count?: number): void;
    incrementLibrariesUpdated(count?: number): void;
    incrementActivitiesProcessed(count?: number): void;
    incrementActivitiesInserted(count?: number): void;
    incrementActivitiesUpdated(count?: number): void;
    incrementErrors(count?: number): void;
    finish(): SyncMetrics;
    getCurrentMetrics(): SyncMetrics;
    reset(): void;
}
export type SyncResult<T = any> = {
    status: "success";
    data: T;
    metrics: SyncMetrics;
} | {
    status: "partial";
    data: T;
    metrics: SyncMetrics;
    errors: string[];
} | {
    status: "error";
    error: string;
    metrics: SyncMetrics;
};
export declare function createSyncResult<T>(status: "success" | "partial" | "error", data: T, metrics: SyncMetrics, error?: string, errors?: string[]): SyncResult<T>;
//# sourceMappingURL=sync-metrics.d.ts.map