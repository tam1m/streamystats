"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.syncServerDataJob = syncServerDataJob;
exports.addServerJob = addServerJob;
exports.sequentialServerSyncJob = sequentialServerSyncJob;
const database_1 = require("@streamystats/database");
const axios_1 = __importDefault(require("axios"));
const drizzle_orm_1 = require("drizzle-orm");
const sync_helpers_1 = require("./sync-helpers");
const job_logger_1 = require("./job-logger");
const config_1 = require("./config");
// Job: Sync server data from external media server API
async function syncServerDataJob(job) {
    const startTime = Date.now();
    const { serverId, endpoint } = job.data;
    try {
        console.log(`Syncing server data for server ID: ${serverId}`);
        // Get server configuration
        const serverData = await database_1.db
            .select()
            .from(database_1.servers)
            .where((0, drizzle_orm_1.eq)(database_1.servers.id, serverId))
            .limit(1);
        if (!serverData.length) {
            throw new Error(`Sync server data: Server with ID ${serverId} not found`);
        }
        const server = serverData[0];
        let response;
        let syncedCount = 0;
        // Handle ActivityLog endpoint differently as it needs /Entries suffix
        if (endpoint === "System/ActivityLog") {
            response = await axios_1.default.get(`${server.url}/System/ActivityLog/Entries`, {
                headers: {
                    "X-Emby-Token": server.apiKey,
                    "Content-Type": "application/json",
                },
            });
        }
        else {
            response = await axios_1.default.get(`${server.url}/${endpoint}`, {
                headers: {
                    "X-Emby-Token": server.apiKey,
                    "Content-Type": "application/json",
                },
            });
        }
        // Handle different endpoint types
        switch (endpoint) {
            case "Users":
                syncedCount = await (0, sync_helpers_1.syncUsers)(server.id, response.data);
                break;
            case "Library/VirtualFolders":
                syncedCount = await (0, sync_helpers_1.syncLibraries)(server.id, response.data);
                break;
            case "System/ActivityLog":
                syncedCount = await (0, sync_helpers_1.syncActivities)(server.id, response.data.Items || []);
                break;
            default:
                throw new Error(`Unknown endpoint: ${endpoint}`);
        }
        const processingTime = Date.now() - startTime;
        await (0, job_logger_1.logJobResult)(job.id, "sync-server-data", "completed", { syncedCount, endpoint }, processingTime);
        return { success: true, syncedCount, endpoint };
    }
    catch (error) {
        const processingTime = Date.now() - startTime;
        await (0, job_logger_1.logJobResult)(job.id, "sync-server-data", "failed", null, processingTime, error);
        throw error;
    }
}
// Job: Add a new media server
async function addServerJob(job) {
    const startTime = Date.now();
    const { name, url, apiKey } = job.data;
    try {
        console.log(`Adding new server: ${name}`);
        // Test server connection
        const response = await axios_1.default.get(`${url}/System/Info`, {
            headers: {
                "X-Emby-Token": apiKey,
                "Content-Type": "application/json",
            },
        });
        const serverInfo = response.data;
        // Create server record
        const newServer = {
            name,
            url,
            apiKey,
            lastSyncedPlaybackId: 0,
            localAddress: serverInfo.LocalAddress,
            version: serverInfo.Version,
            productName: serverInfo.ProductName,
            operatingSystem: serverInfo.OperatingSystem,
            startupWizardCompleted: serverInfo.StartupWizardCompleted || false,
            autoGenerateEmbeddings: false,
        };
        const insertedServers = await database_1.db
            .insert(database_1.servers)
            .values(newServer)
            .returning();
        const processingTime = Date.now() - startTime;
        await (0, job_logger_1.logJobResult)(job.id, "add-server", "completed", insertedServers[0], processingTime);
        return { success: true, server: insertedServers[0] };
    }
    catch (error) {
        const processingTime = Date.now() - startTime;
        await (0, job_logger_1.logJobResult)(job.id, "add-server", "failed", null, processingTime, error);
        throw error;
    }
}
// Job: Sequential server sync - syncs users, libraries, items, and activities in order
async function sequentialServerSyncJob(job) {
    const startTime = Date.now();
    const { serverId } = job.data;
    try {
        console.log(`Starting sequential sync for server ID: ${serverId}`);
        // Update server status to syncing
        await database_1.db
            .update(database_1.servers)
            .set({
            syncStatus: "syncing",
            syncProgress: "users",
            lastSyncStarted: new Date(),
            syncError: null,
        })
            .where((0, drizzle_orm_1.eq)(database_1.servers.id, serverId));
        // Get server configuration
        const serverData = await database_1.db
            .select()
            .from(database_1.servers)
            .where((0, drizzle_orm_1.eq)(database_1.servers.id, serverId))
            .limit(1);
        if (!serverData.length) {
            console.warn(`Sequential sync: Server with ID ${serverId} not found, possibly deleted. Skipping job.`);
            const processingTime = Date.now() - startTime;
            await (0, job_logger_1.logJobResult)(job.id, "sequential-server-sync", "completed", { skipped: true, reason: "Server not found" }, processingTime);
            return { success: true, skipped: true, reason: "Server not found" };
        }
        const server = serverData[0];
        const syncResults = {
            users: 0,
            libraries: 0,
            items: 0,
            activities: 0,
        };
        // Step 1: Sync Users
        console.log(`Syncing users for server ${serverId}`);
        try {
            const usersResponse = await axios_1.default.get(`${server.url}/Users`, {
                headers: {
                    "X-Emby-Token": server.apiKey,
                    "Content-Type": "application/json",
                },
                timeout: config_1.TIMEOUT_CONFIG.DEFAULT,
            });
            syncResults.users = await (0, sync_helpers_1.syncUsers)(serverId, usersResponse.data);
            console.log(`Synced ${syncResults.users} users`);
        }
        catch (error) {
            console.error("Error syncing users:", error);
            const errorMessage = axios_1.default.isAxiosError(error)
                ? `API Error: ${error.response?.status} - ${error.response?.statusText || error.message}`
                : `Database Error: ${error instanceof Error ? error.message : String(error)}`;
            throw new Error(`Failed to sync users: ${errorMessage}`);
        }
        // Update progress to libraries
        await database_1.db
            .update(database_1.servers)
            .set({ syncProgress: "libraries" })
            .where((0, drizzle_orm_1.eq)(database_1.servers.id, serverId));
        // Step 2: Sync Libraries
        console.log(`Syncing libraries for server ${serverId}`);
        try {
            const librariesResponse = await axios_1.default.get(`${server.url}/Library/VirtualFolders`, {
                headers: {
                    "X-Emby-Token": server.apiKey,
                    "Content-Type": "application/json",
                },
                timeout: config_1.TIMEOUT_CONFIG.DEFAULT,
            });
            syncResults.libraries = await (0, sync_helpers_1.syncLibraries)(serverId, librariesResponse.data);
            console.log(`Synced ${syncResults.libraries} libraries`);
        }
        catch (error) {
            console.error("Error syncing libraries:", error);
            const errorMessage = axios_1.default.isAxiosError(error)
                ? `API Error: ${error.response?.status} - ${error.response?.statusText || error.message}`
                : `Database Error: ${error instanceof Error ? error.message : String(error)}`;
            throw new Error(`Failed to sync libraries: ${errorMessage}`);
        }
        // Update progress to items
        await database_1.db
            .update(database_1.servers)
            .set({ syncProgress: "items" })
            .where((0, drizzle_orm_1.eq)(database_1.servers.id, serverId));
        // Step 3: Sync Items (for each library)
        console.log(`Syncing items for server ${serverId}`);
        try {
            const librariesData = await database_1.db
                .select()
                .from(database_1.libraries)
                .where((0, drizzle_orm_1.eq)(database_1.libraries.serverId, serverId));
            for (const library of librariesData) {
                const itemsResponse = await axios_1.default.get(`${server.url}/Items?ParentId=${library.id}&Recursive=true&Fields=BasicSyncInfo,MediaSourceCount,Path,Genres`, {
                    headers: {
                        "X-Emby-Token": server.apiKey,
                        "Content-Type": "application/json",
                    },
                    timeout: config_1.TIMEOUT_CONFIG.ITEMS_SYNC,
                });
                const itemsSynced = await (0, sync_helpers_1.syncItems)(serverId, library.id, itemsResponse.data.Items || []);
                syncResults.items += itemsSynced;
                console.log(`Synced ${itemsSynced} items for library ${library.name}`);
            }
            console.log(`Total synced ${syncResults.items} items`);
        }
        catch (error) {
            console.error("Error syncing items:", error);
            const errorMessage = axios_1.default.isAxiosError(error)
                ? `API Error: ${error.response?.status} - ${error.response?.statusText || error.message}`
                : `Database Error: ${error instanceof Error ? error.message : String(error)}`;
            throw new Error(`Failed to sync items: ${errorMessage}`);
        }
        // Update progress to activities
        await database_1.db
            .update(database_1.servers)
            .set({ syncProgress: "activities" })
            .where((0, drizzle_orm_1.eq)(database_1.servers.id, serverId));
        // Step 4: Sync Activities
        console.log(`Syncing activities for server ${serverId}`);
        try {
            const activitiesResponse = await axios_1.default.get(`${server.url}/System/ActivityLog/Entries`, {
                headers: {
                    "X-Emby-Token": server.apiKey,
                    "Content-Type": "application/json",
                },
                timeout: config_1.TIMEOUT_CONFIG.DEFAULT,
            });
            syncResults.activities = await (0, sync_helpers_1.syncActivities)(serverId, activitiesResponse.data.Items || []);
            console.log(`Synced ${syncResults.activities} activities`);
        }
        catch (error) {
            console.error("Error syncing activities:", error);
            const errorMessage = axios_1.default.isAxiosError(error)
                ? `API Error: ${error.response?.status} - ${error.response?.statusText || error.message}`
                : `Database Error: ${error instanceof Error ? error.message : String(error)}`;
            throw new Error(`Failed to sync activities: ${errorMessage}`);
        }
        // Update server status to completed
        await database_1.db
            .update(database_1.servers)
            .set({
            syncStatus: "completed",
            syncProgress: "completed",
            lastSyncCompleted: new Date(),
        })
            .where((0, drizzle_orm_1.eq)(database_1.servers.id, serverId));
        const processingTime = Date.now() - startTime;
        await (0, job_logger_1.logJobResult)(job.id, "sequential-server-sync", "completed", syncResults, processingTime);
        console.log(`Sequential sync completed for server ${serverId}:`, syncResults);
        return { success: true, syncResults };
    }
    catch (error) {
        console.error(`Sequential sync failed for server ${serverId}:`, error);
        // Update server status to failed
        await database_1.db
            .update(database_1.servers)
            .set({
            syncStatus: "failed",
            syncError: error instanceof Error ? error.message : String(error),
        })
            .where((0, drizzle_orm_1.eq)(database_1.servers.id, serverId));
        const processingTime = Date.now() - startTime;
        await (0, job_logger_1.logJobResult)(job.id, "sequential-server-sync", "failed", null, processingTime, error instanceof Error ? error.message : String(error));
        throw error;
    }
}
