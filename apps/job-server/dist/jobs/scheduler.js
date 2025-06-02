"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.activityScheduler = void 0;
const cron = __importStar(require("node-cron"));
const database_1 = require("@streamystats/database");
const drizzle_orm_1 = require("drizzle-orm");
const queue_1 = require("./queue");
const workers_1 = require("../jellyfin/workers");
class SyncScheduler {
    scheduledTasks = new Map();
    enabled = false;
    activitySyncInterval = "*/5 * * * *"; // Every 5 minutes
    recentItemsSyncInterval = "*/5 * * * *"; // Every 15 minutes
    jobCleanupInterval = "*/5 * * * *"; // Every 5 minutes
    constructor() {
        // Auto-start if not explicitly disabled
        const autoStart = process.env.SCHEDULER_AUTO_START !== "false";
        if (autoStart) {
            this.start();
        }
    }
    /**
     * Start the scheduler with current configuration
     */
    start() {
        if (this.enabled) {
            console.log("Scheduler is already running");
            return;
        }
        this.enabled = true;
        try {
            // Activity sync task
            const activityTask = cron.schedule(this.activitySyncInterval, () => {
                this.triggerActivitySync().catch((error) => {
                    console.error("Error during scheduled activity sync:", error);
                });
            });
            // Recent items sync task
            const recentItemsTask = cron.schedule(this.recentItemsSyncInterval, () => {
                this.triggerRecentItemsSync().catch((error) => {
                    console.error("Error during scheduled recent items sync:", error);
                });
            });
            // Job cleanup task for stale embedding jobs
            const jobCleanupTask = cron.schedule(this.jobCleanupInterval, () => {
                this.triggerJobCleanup().catch((error) => {
                    console.error("Error during scheduled job cleanup:", error);
                });
            });
            this.scheduledTasks.set("activity-sync", activityTask);
            this.scheduledTasks.set("recent-items-sync", recentItemsTask);
            this.scheduledTasks.set("job-cleanup", jobCleanupTask);
            // Start all tasks
            activityTask.start();
            recentItemsTask.start();
            jobCleanupTask.start();
            console.log("Scheduler started successfully");
            console.log(`Activity sync: ${this.activitySyncInterval}`);
            console.log(`Recent items sync: ${this.recentItemsSyncInterval}`);
            console.log(`Job cleanup: ${this.jobCleanupInterval}`);
        }
        catch (error) {
            console.error("Failed to start scheduler:", error);
            this.enabled = false;
            throw error;
        }
    }
    /**
     * Stop the scheduler
     */
    stop() {
        if (!this.enabled) {
            console.log("Scheduler is not running");
            return;
        }
        // Stop and clear all scheduled tasks
        for (const [name, task] of this.scheduledTasks) {
            try {
                task.stop();
                task.destroy();
                console.log(`Stopped scheduled task: ${name}`);
            }
            catch (error) {
                console.error(`Error stopping task ${name}:`, error);
            }
        }
        this.scheduledTasks.clear();
        this.enabled = false;
        console.log("Scheduler stopped");
    }
    /**
     * Update scheduler configuration
     */
    updateConfig(config) {
        const wasEnabled = this.enabled;
        if (config.activitySyncInterval) {
            this.activitySyncInterval = config.activitySyncInterval;
        }
        if (config.recentItemsSyncInterval) {
            this.recentItemsSyncInterval = config.recentItemsSyncInterval;
        }
        if (config.jobCleanupInterval) {
            this.jobCleanupInterval = config.jobCleanupInterval;
        }
        if (config.enabled !== undefined && config.enabled !== this.enabled) {
            if (config.enabled) {
                this.start();
            }
            else {
                this.stop();
            }
        }
        else if (wasEnabled && this.enabled) {
            // Restart with new configuration if it was running
            this.stop();
            this.start();
        }
    }
    /**
     * Trigger activity sync for all active servers
     */
    async triggerActivitySync() {
        try {
            console.log("Triggering periodic activity sync...");
            // Get all servers that are not currently syncing
            const activeServers = await database_1.db
                .select()
                .from(database_1.servers)
                .where((0, drizzle_orm_1.eq)(database_1.servers.syncStatus, "completed"));
            if (activeServers.length === 0) {
                console.log("No active servers found for activity sync");
                return;
            }
            const boss = await (0, queue_1.getJobQueue)();
            // Queue activity sync jobs for each server
            for (const server of activeServers) {
                try {
                    await boss.send(workers_1.JELLYFIN_JOB_NAMES.RECENT_ACTIVITIES_SYNC, {
                        serverId: server.id,
                        options: {
                            activityOptions: {
                                limit: 100, // Default limit
                            },
                        },
                    }, {
                        expireInMinutes: 30, // Job expires after 30 minutes
                        retryLimit: 1, // Retry once if it fails
                        retryDelay: 60, // Wait 60 seconds before retrying
                    });
                    console.log(`Queued periodic activity sync for server: ${server.name} (ID: ${server.id})`);
                }
                catch (error) {
                    console.error(`Failed to queue activity sync for server ${server.name}:`, error);
                }
            }
            console.log(`Periodic activity sync queued for ${activeServers.length} servers`);
        }
        catch (error) {
            console.error("Error during periodic activity sync trigger:", error);
        }
    }
    /**
     * Trigger recently added items sync for all active servers
     */
    async triggerRecentItemsSync() {
        try {
            console.log("Triggering periodic recently added items sync...");
            // Get all servers that are not currently syncing
            const activeServers = await database_1.db
                .select()
                .from(database_1.servers)
                .where((0, drizzle_orm_1.eq)(database_1.servers.syncStatus, "completed"));
            if (activeServers.length === 0) {
                console.log("No active servers found for recently added items sync");
                return;
            }
            const boss = await (0, queue_1.getJobQueue)();
            // Queue recently added items sync jobs for each server
            for (const server of activeServers) {
                try {
                    await boss.send(workers_1.JELLYFIN_JOB_NAMES.RECENT_ITEMS_SYNC, {
                        serverId: server.id,
                        options: {
                            itemOptions: {
                                recentItemsLimit: 100, // Default limit
                            },
                        },
                    }, {
                        expireInMinutes: 30, // Job expires after 30 minutes
                        retryLimit: 1, // Retry once if it fails
                        retryDelay: 60, // Wait 60 seconds before retrying
                    });
                    console.log(`Queued periodic recently added items sync for server: ${server.name} (ID: ${server.id})`);
                }
                catch (error) {
                    console.error(`Failed to queue recently added items sync for server ${server.name}:`, error);
                }
            }
            console.log(`Periodic recently added items sync queued for ${activeServers.length} servers`);
        }
        catch (error) {
            console.error("Error during periodic recently added items sync trigger:", error);
        }
    }
    /**
     * Trigger cleanup of stale embedding jobs
     */
    async triggerJobCleanup() {
        try {
            // Find all processing embedding jobs older than 10 minutes
            const staleJobs = await database_1.db
                .select()
                .from(database_1.jobResults)
                .where((0, drizzle_orm_1.and)((0, drizzle_orm_1.eq)(database_1.jobResults.jobName, "generate-item-embeddings"), (0, drizzle_orm_1.eq)(database_1.jobResults.status, "processing"), (0, drizzle_orm_1.sql) `${database_1.jobResults.createdAt} < NOW() - INTERVAL '10 minutes'`));
            let cleanedCount = 0;
            for (const staleJob of staleJobs) {
                try {
                    const result = staleJob.result;
                    const serverId = result?.serverId;
                    if (serverId) {
                        // Check if there's been recent heartbeat activity
                        const lastHeartbeat = result?.lastHeartbeat
                            ? new Date(result.lastHeartbeat).getTime()
                            : new Date(staleJob.createdAt).getTime();
                        const heartbeatAge = Date.now() - lastHeartbeat;
                        // Only cleanup if no recent heartbeat (older than 2 minutes)
                        if (heartbeatAge > 2 * 60 * 1000) {
                            await database_1.db.insert(database_1.jobResults).values({
                                jobId: `cleanup-${serverId}-${Date.now()}`,
                                jobName: "generate-item-embeddings",
                                status: "failed",
                                result: {
                                    serverId,
                                    error: "Job cleanup - exceeded maximum processing time",
                                    cleanedAt: new Date().toISOString(),
                                    originalJobId: staleJob.jobId,
                                    staleDuration: heartbeatAge,
                                },
                                processingTime: Date.now() - new Date(staleJob.createdAt).getTime(),
                                error: "Job exceeded maximum processing time without heartbeat",
                            });
                            cleanedCount++;
                            console.log(`Cleaned up stale embedding job for server ${serverId}`);
                        }
                    }
                }
                catch (error) {
                    console.error("Error cleaning up stale job:", staleJob.jobId, error);
                }
            }
            if (cleanedCount > 0) {
                console.log(`Job cleanup completed: cleaned ${cleanedCount} stale embedding jobs`);
            }
        }
        catch (error) {
            console.error("Error during job cleanup:", error);
        }
    }
    /**
     * Manually trigger activity sync for a specific server
     */
    async triggerServerActivitySync(serverId, limit = 100) {
        try {
            const boss = await (0, queue_1.getJobQueue)();
            await boss.send(workers_1.JELLYFIN_JOB_NAMES.RECENT_ACTIVITIES_SYNC, {
                serverId,
                options: {
                    activityOptions: {
                        limit,
                    },
                },
            }, {
                expireInMinutes: 30, // Job expires after 30 minutes
                retryLimit: 1, // Retry once if it fails
                retryDelay: 60, // Wait 60 seconds before retrying
            });
            console.log(`Manual activity sync queued for server ID: ${serverId} (limit: ${limit})`);
        }
        catch (error) {
            console.error(`Failed to queue manual activity sync for server ${serverId}:`, error);
            throw error;
        }
    }
    /**
     * Manually trigger recently added items sync for a specific server
     */
    async triggerServerRecentItemsSync(serverId, limit = 100) {
        try {
            const boss = await (0, queue_1.getJobQueue)();
            await boss.send(workers_1.JELLYFIN_JOB_NAMES.RECENT_ITEMS_SYNC, {
                serverId,
                options: {
                    itemOptions: {
                        recentItemsLimit: limit,
                    },
                },
            }, {
                expireInMinutes: 30, // Job expires after 30 minutes
                retryLimit: 1, // Retry once if it fails
                retryDelay: 60, // Wait 60 seconds before retrying
            });
            console.log(`Manual recently added items sync queued for server ID: ${serverId} (limit: ${limit})`);
        }
        catch (error) {
            console.error(`Failed to queue manual recently added items sync for server ${serverId}:`, error);
            throw error;
        }
    }
    /**
     * Get current scheduler status
     */
    getStatus() {
        return {
            enabled: this.enabled,
            activitySyncInterval: this.activitySyncInterval,
            recentItemsSyncInterval: this.recentItemsSyncInterval,
            jobCleanupInterval: this.jobCleanupInterval,
            runningTasks: Array.from(this.scheduledTasks.keys()),
            healthCheck: this.enabled,
        };
    }
}
// Export singleton instance
exports.activityScheduler = new SyncScheduler();
