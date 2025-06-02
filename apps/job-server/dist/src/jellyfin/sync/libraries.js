"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.syncLibraries = syncLibraries;
const drizzle_orm_1 = require("drizzle-orm");
const connection_1 = require("../../db/connection");
const schema_1 = require("../../db/schema");
const client_1 = require("../client");
const sync_metrics_1 = require("../sync-metrics");
const p_map_1 = __importDefault(require("p-map"));
async function syncLibraries(server, options = {}) {
    const { batchSize = 100, concurrency = 5 } = options;
    const metrics = new sync_metrics_1.SyncMetricsTracker();
    const client = client_1.JellyfinClient.fromServer(server);
    const errors = [];
    try {
        console.log(`Starting library sync for server ${server.name}`);
        // Fetch libraries from Jellyfin
        metrics.incrementApiRequests();
        const jellyfinLibraries = await client.getLibraries();
        console.log(`Fetched ${jellyfinLibraries.length} libraries from Jellyfin`);
        // Process libraries in batches with controlled concurrency
        let librariesInserted = 0;
        let librariesUpdated = 0;
        await (0, p_map_1.default)(jellyfinLibraries, async (jellyfinLibrary) => {
            try {
                const wasInserted = await processLibrary(jellyfinLibrary, server.id, metrics);
                if (wasInserted) {
                    librariesInserted++;
                    metrics.incrementLibrariesInserted();
                }
                else {
                    librariesUpdated++;
                    metrics.incrementLibrariesUpdated();
                }
                metrics.incrementLibrariesProcessed();
            }
            catch (error) {
                console.error(`Error processing library ${jellyfinLibrary.Id}:`, error);
                metrics.incrementErrors();
                errors.push(`Library ${jellyfinLibrary.Id}: ${error instanceof Error ? error.message : "Unknown error"}`);
            }
        }, { concurrency });
        const finalMetrics = metrics.finish();
        const data = {
            librariesProcessed: finalMetrics.librariesProcessed,
            librariesInserted: finalMetrics.librariesInserted,
            librariesUpdated: finalMetrics.librariesUpdated,
        };
        console.log(`Library sync completed for server ${server.name}:`, data);
        if (errors.length > 0) {
            return (0, sync_metrics_1.createSyncResult)("partial", data, finalMetrics, undefined, errors);
        }
        return (0, sync_metrics_1.createSyncResult)("success", data, finalMetrics);
    }
    catch (error) {
        console.error(`Library sync failed for server ${server.name}:`, error);
        const finalMetrics = metrics.finish();
        const errorData = {
            librariesProcessed: finalMetrics.librariesProcessed,
            librariesInserted: finalMetrics.librariesInserted,
            librariesUpdated: finalMetrics.librariesUpdated,
        };
        return (0, sync_metrics_1.createSyncResult)("error", errorData, finalMetrics, error instanceof Error ? error.message : "Unknown error");
    }
}
async function processLibrary(jellyfinLibrary, serverId, metrics) {
    // Check if library already exists
    const existingLibrary = await connection_1.db
        .select()
        .from(schema_1.libraries)
        .where((0, drizzle_orm_1.eq)(schema_1.libraries.id, jellyfinLibrary.Id))
        .limit(1);
    const libraryData = {
        id: jellyfinLibrary.Id,
        name: jellyfinLibrary.Name,
        type: jellyfinLibrary.CollectionType || jellyfinLibrary.Type || "Unknown",
        serverId,
        updatedAt: new Date(),
    };
    const isNewLibrary = existingLibrary.length === 0;
    // Upsert library (insert or update if exists)
    await connection_1.db
        .insert(schema_1.libraries)
        .values(libraryData)
        .onConflictDoUpdate({
        target: schema_1.libraries.id,
        set: {
            ...libraryData,
            updatedAt: new Date(),
        },
    });
    metrics.incrementDatabaseOperations();
    return isNewLibrary;
}
