"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.SyncMetricsTracker = void 0;
exports.createSyncResult = createSyncResult;
class SyncMetricsTracker {
    constructor() {
        this.metrics = {
            apiRequests: 0,
            databaseOperations: 0,
            itemsProcessed: 0,
            itemsInserted: 0,
            itemsUpdated: 0,
            itemsUnchanged: 0,
            usersProcessed: 0,
            usersInserted: 0,
            usersUpdated: 0,
            librariesProcessed: 0,
            librariesInserted: 0,
            librariesUpdated: 0,
            activitiesProcessed: 0,
            activitiesInserted: 0,
            activitiesUpdated: 0,
            errors: 0,
            startTime: new Date(),
        };
    }
    incrementApiRequests(count = 1) {
        this.metrics.apiRequests += count;
    }
    incrementDatabaseOperations(count = 1) {
        this.metrics.databaseOperations += count;
    }
    incrementItemsProcessed(count = 1) {
        this.metrics.itemsProcessed += count;
    }
    incrementItemsInserted(count = 1) {
        this.metrics.itemsInserted += count;
    }
    incrementItemsUpdated(count = 1) {
        this.metrics.itemsUpdated += count;
    }
    incrementItemsUnchanged(count = 1) {
        this.metrics.itemsUnchanged += count;
    }
    incrementUsersProcessed(count = 1) {
        this.metrics.usersProcessed += count;
    }
    incrementUsersInserted(count = 1) {
        this.metrics.usersInserted += count;
    }
    incrementUsersUpdated(count = 1) {
        this.metrics.usersUpdated += count;
    }
    incrementLibrariesProcessed(count = 1) {
        this.metrics.librariesProcessed += count;
    }
    incrementLibrariesInserted(count = 1) {
        this.metrics.librariesInserted += count;
    }
    incrementLibrariesUpdated(count = 1) {
        this.metrics.librariesUpdated += count;
    }
    incrementActivitiesProcessed(count = 1) {
        this.metrics.activitiesProcessed += count;
    }
    incrementActivitiesInserted(count = 1) {
        this.metrics.activitiesInserted += count;
    }
    incrementActivitiesUpdated(count = 1) {
        this.metrics.activitiesUpdated += count;
    }
    incrementErrors(count = 1) {
        this.metrics.errors += count;
    }
    finish() {
        this.metrics.endTime = new Date();
        this.metrics.duration =
            this.metrics.endTime.getTime() - this.metrics.startTime.getTime();
        return { ...this.metrics };
    }
    getCurrentMetrics() {
        return { ...this.metrics };
    }
    reset() {
        this.metrics = {
            apiRequests: 0,
            databaseOperations: 0,
            itemsProcessed: 0,
            itemsInserted: 0,
            itemsUpdated: 0,
            itemsUnchanged: 0,
            usersProcessed: 0,
            usersInserted: 0,
            usersUpdated: 0,
            librariesProcessed: 0,
            librariesInserted: 0,
            librariesUpdated: 0,
            activitiesProcessed: 0,
            activitiesInserted: 0,
            activitiesUpdated: 0,
            errors: 0,
            startTime: new Date(),
        };
    }
}
exports.SyncMetricsTracker = SyncMetricsTracker;
function createSyncResult(status, data, metrics, error, errors) {
    if (status === "error") {
        return { status, error: error || "Unknown error", metrics };
    }
    if (status === "partial") {
        return { status, data, metrics, errors: errors || [] };
    }
    return { status, data, metrics };
}
