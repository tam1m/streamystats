"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.syncRecentActivities = exports.syncActivities = exports.syncRecentlyAddedItems = exports.syncItems = exports.syncLibraries = exports.syncUsers = exports.DEFAULT_SYNC_OPTIONS = void 0;
exports.performFullSync = performFullSync;
exports.getDefaultOptions = getDefaultOptions;
const users_1 = require("./users");
Object.defineProperty(exports, "syncUsers", { enumerable: true, get: function () { return users_1.syncUsers; } });
const libraries_1 = require("./libraries");
Object.defineProperty(exports, "syncLibraries", { enumerable: true, get: function () { return libraries_1.syncLibraries; } });
const items_1 = require("./items");
Object.defineProperty(exports, "syncItems", { enumerable: true, get: function () { return items_1.syncItems; } });
Object.defineProperty(exports, "syncRecentlyAddedItems", { enumerable: true, get: function () { return items_1.syncRecentlyAddedItems; } });
const activities_1 = require("./activities");
Object.defineProperty(exports, "syncActivities", { enumerable: true, get: function () { return activities_1.syncActivities; } });
Object.defineProperty(exports, "syncRecentActivities", { enumerable: true, get: function () { return activities_1.syncRecentActivities; } });
const sync_metrics_1 = require("../sync-metrics");
// Default sync options based on the Elixir configuration
exports.DEFAULT_SYNC_OPTIONS = {
    maxLibraryConcurrency: 2,
    dbBatchSize: 1000,
    apiRequestDelayMs: 100,
    maxRetries: 3,
    retryInitialDelayMs: 1000,
    adaptiveThrottling: true,
};
/**
 * Main sync coordinator - performs a full sync of all data types
 */
async function performFullSync(server, options = {}) {
    const finalOptions = { ...exports.DEFAULT_SYNC_OPTIONS, ...options };
    const globalMetrics = new sync_metrics_1.SyncMetricsTracker();
    const errors = [];
    console.log(`Starting full sync for server ${server.name}`);
    try {
        // 1. Sync Users
        console.log("Step 1/4: Syncing users...");
        const usersResult = await (0, users_1.syncUsers)(server, finalOptions.userOptions);
        if (usersResult.status === "error") {
            console.error("Users sync failed:", usersResult.error);
            errors.push(`Users: ${usersResult.error}`);
        }
        else if (usersResult.status === "partial") {
            console.warn("Users sync completed with errors:", usersResult.errors);
            errors.push(...usersResult.errors.map((e) => `Users: ${e}`));
        }
        console.log("Users sync completed:", usersResult.status === "error" ? "FAILED" : usersResult.data);
        // 2. Sync Libraries
        console.log("Step 2/4: Syncing libraries...");
        const librariesResult = await (0, libraries_1.syncLibraries)(server, finalOptions.libraryOptions);
        if (librariesResult.status === "error") {
            console.error("Libraries sync failed:", librariesResult.error);
            errors.push(`Libraries: ${librariesResult.error}`);
        }
        else if (librariesResult.status === "partial") {
            console.warn("Libraries sync completed with errors:", librariesResult.errors);
            errors.push(...librariesResult.errors.map((e) => `Libraries: ${e}`));
        }
        console.log("Libraries sync completed:", librariesResult.status === "error" ? "FAILED" : librariesResult.data);
        // 3. Sync Items (this will take the longest)
        console.log("Step 3/4: Syncing items...");
        const itemsResult = await (0, items_1.syncItems)(server, {
            ...finalOptions.itemOptions,
            maxLibraryConcurrency: finalOptions.maxLibraryConcurrency,
            apiRequestDelayMs: finalOptions.apiRequestDelayMs,
        });
        if (itemsResult.status === "error") {
            console.error("Items sync failed:", itemsResult.error);
            errors.push(`Items: ${itemsResult.error}`);
        }
        else if (itemsResult.status === "partial") {
            console.warn("Items sync completed with errors:", itemsResult.errors);
            errors.push(...itemsResult.errors.map((e) => `Items: ${e}`));
        }
        console.log("Items sync completed:", itemsResult.status === "error" ? "FAILED" : itemsResult.data);
        // 4. Sync Activities
        console.log("Step 4/4: Syncing activities...");
        const activitiesResult = await (0, activities_1.syncActivities)(server, finalOptions.activityOptions);
        if (activitiesResult.status === "error") {
            console.error("Activities sync failed:", activitiesResult.error);
            errors.push(`Activities: ${activitiesResult.error}`);
        }
        else if (activitiesResult.status === "partial") {
            console.warn("Activities sync completed with errors:", activitiesResult.errors);
            errors.push(...activitiesResult.errors.map((e) => `Activities: ${e}`));
        }
        console.log("Activities sync completed:", activitiesResult.status === "error" ? "FAILED" : activitiesResult.data);
        const finalMetrics = globalMetrics.finish();
        // Helper function to safely extract data from sync results
        const getSyncData = (result, defaultValue) => {
            return result.status === "error" ? defaultValue : result.data;
        };
        const fullSyncData = {
            users: getSyncData(usersResult, {
                usersProcessed: 0,
                usersInserted: 0,
                usersUpdated: 0,
            }),
            libraries: getSyncData(librariesResult, {
                librariesProcessed: 0,
                librariesInserted: 0,
                librariesUpdated: 0,
            }),
            items: getSyncData(itemsResult, {
                librariesProcessed: 0,
                itemsProcessed: 0,
                itemsInserted: 0,
                itemsUpdated: 0,
                itemsUnchanged: 0,
            }),
            activities: getSyncData(activitiesResult, {
                activitiesProcessed: 0,
                activitiesInserted: 0,
                activitiesUpdated: 0,
                pagesFetched: 0,
            }),
            totalDuration: finalMetrics.duration || 0,
        };
        console.log(`Full sync completed for server ${server.name}:`, {
            totalDuration: `${finalMetrics.duration || 0}ms`,
            errors: errors.length,
        });
        // Determine overall result
        const hasErrors = [
            usersResult,
            librariesResult,
            itemsResult,
            activitiesResult,
        ].some((result) => result.status === "error");
        const hasPartialErrors = [
            usersResult,
            librariesResult,
            itemsResult,
            activitiesResult,
        ].some((result) => result.status === "partial");
        if (hasErrors) {
            return (0, sync_metrics_1.createSyncResult)("error", fullSyncData, finalMetrics, "One or more sync operations failed", errors);
        }
        else if (hasPartialErrors || errors.length > 0) {
            return (0, sync_metrics_1.createSyncResult)("partial", fullSyncData, finalMetrics, undefined, errors);
        }
        else {
            return (0, sync_metrics_1.createSyncResult)("success", fullSyncData, finalMetrics);
        }
    }
    catch (error) {
        console.error(`Full sync failed for server ${server.name}:`, error);
        const finalMetrics = globalMetrics.finish();
        const errorData = {
            users: { usersProcessed: 0, usersInserted: 0, usersUpdated: 0 },
            libraries: {
                librariesProcessed: 0,
                librariesInserted: 0,
                librariesUpdated: 0,
            },
            items: {
                librariesProcessed: 0,
                itemsProcessed: 0,
                itemsInserted: 0,
                itemsUpdated: 0,
                itemsUnchanged: 0,
            },
            activities: {
                activitiesProcessed: 0,
                activitiesInserted: 0,
                activitiesUpdated: 0,
                pagesFetched: 0,
            },
            totalDuration: finalMetrics.duration || 0,
        };
        return (0, sync_metrics_1.createSyncResult)("error", errorData, finalMetrics, error instanceof Error ? error.message : "Unknown error");
    }
}
/**
 * Returns the default synchronization options.
 * These can be overridden by passing a map of options to the sync functions.
 */
function getDefaultOptions() {
    return { ...exports.DEFAULT_SYNC_OPTIONS };
}
