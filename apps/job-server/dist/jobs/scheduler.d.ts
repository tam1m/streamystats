interface SchedulerConfig {
    activitySyncInterval?: string;
    recentItemsSyncInterval?: string;
    enabled?: boolean;
}
declare class SyncScheduler {
    private scheduledTasks;
    private config;
    constructor(config?: SchedulerConfig);
    /**
     * Start the periodic sync scheduler
     */
    start(): Promise<void>;
    /**
     * Stop all scheduled tasks
     */
    stop(): void;
    /**
     * Trigger activity sync for all active servers
     */
    private triggerActivitySync;
    /**
     * Trigger recently added items sync for all active servers
     */
    private triggerRecentItemsSync;
    /**
     * Manually trigger activity sync for a specific server
     */
    triggerServerActivitySync(serverId: number): Promise<void>;
    /**
     * Manually trigger recently added items sync for a specific server
     */
    triggerServerRecentItemsSync(serverId: number, limit?: number): Promise<void>;
    /**
     * Update scheduler configuration
     */
    updateConfig(config: Partial<SchedulerConfig>): void;
    /**
     * Get current scheduler status
     */
    getStatus(): {
        enabled: boolean;
        activitySyncInterval: string;
        recentItemsSyncInterval: string;
        runningTasks: string[];
    };
}
export declare const activityScheduler: SyncScheduler;
export declare const syncScheduler: SyncScheduler;
export { SyncScheduler, SchedulerConfig };
//# sourceMappingURL=scheduler.d.ts.map