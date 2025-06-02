"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.JELLYFIN_JOB_NAMES = exports.jellyfinRecentActivitiesSyncWorker = exports.jellyfinRecentItemsSyncWorker = exports.jellyfinActivitiesSyncWorker = exports.jellyfinItemsSyncWorker = exports.jellyfinLibrariesSyncWorker = exports.jellyfinUsersSyncWorker = exports.jellyfinFullSyncWorker = exports.jellyfinSyncWorker = void 0;
exports.syncServerDataJob = syncServerDataJob;
exports.addServerJob = addServerJob;
exports.generateMediaEmbeddingsJob = generateMediaEmbeddingsJob;
exports.fetchExternalDataJob = fetchExternalDataJob;
exports.generateEmbeddingsJob = generateEmbeddingsJob;
exports.batchProcessPostsJob = batchProcessPostsJob;
exports.customProcessingJob = customProcessingJob;
exports.sequentialServerSyncJob = sequentialServerSyncJob;
const axios_1 = __importDefault(require("axios"));
const openai_1 = __importDefault(require("openai"));
const connection_1 = require("../db/connection");
const schema_1 = require("../db/schema");
const drizzle_orm_1 = require("drizzle-orm");
// Import Jellyfin sync workers
const workers_1 = require("../jellyfin/workers");
Object.defineProperty(exports, "jellyfinSyncWorker", { enumerable: true, get: function () { return workers_1.jellyfinSyncWorker; } });
Object.defineProperty(exports, "jellyfinFullSyncWorker", { enumerable: true, get: function () { return workers_1.jellyfinFullSyncWorker; } });
Object.defineProperty(exports, "jellyfinUsersSyncWorker", { enumerable: true, get: function () { return workers_1.jellyfinUsersSyncWorker; } });
Object.defineProperty(exports, "jellyfinLibrariesSyncWorker", { enumerable: true, get: function () { return workers_1.jellyfinLibrariesSyncWorker; } });
Object.defineProperty(exports, "jellyfinItemsSyncWorker", { enumerable: true, get: function () { return workers_1.jellyfinItemsSyncWorker; } });
Object.defineProperty(exports, "jellyfinActivitiesSyncWorker", { enumerable: true, get: function () { return workers_1.jellyfinActivitiesSyncWorker; } });
Object.defineProperty(exports, "jellyfinRecentItemsSyncWorker", { enumerable: true, get: function () { return workers_1.jellyfinRecentItemsSyncWorker; } });
Object.defineProperty(exports, "jellyfinRecentActivitiesSyncWorker", { enumerable: true, get: function () { return workers_1.jellyfinRecentActivitiesSyncWorker; } });
Object.defineProperty(exports, "JELLYFIN_JOB_NAMES", { enumerable: true, get: function () { return workers_1.JELLYFIN_JOB_NAMES; } });
// Initialize OpenAI client (optional)
const openai = process.env.OPENAI_API_KEY
    ? new openai_1.default({
        apiKey: process.env.OPENAI_API_KEY,
    })
    : null;
// Job: Sync server data from external media server API
async function syncServerDataJob(job) {
    const startTime = Date.now();
    const { serverId, endpoint } = job.data;
    try {
        console.log(`Syncing server data for server ID: ${serverId}`);
        // Get server configuration
        const serverData = await connection_1.db
            .select()
            .from(schema_1.servers)
            .where((0, drizzle_orm_1.eq)(schema_1.servers.id, serverId))
            .limit(1);
        if (!serverData.length) {
            throw new Error(`Server with ID ${serverId} not found`);
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
                syncedCount = await syncUsers(server.id, response.data);
                break;
            case "Library/VirtualFolders":
                syncedCount = await syncLibraries(server.id, response.data);
                break;
            case "System/ActivityLog":
                syncedCount = await syncActivities(server.id, response.data.Items || []);
                break;
            default:
                throw new Error(`Unknown endpoint: ${endpoint}`);
        }
        const processingTime = Date.now() - startTime;
        await logJobResult(job.id, "sync-server-data", "completed", { syncedCount, endpoint }, processingTime);
        return { success: true, syncedCount, endpoint };
    }
    catch (error) {
        const processingTime = Date.now() - startTime;
        await logJobResult(job.id, "sync-server-data", "failed", null, processingTime, error);
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
            serverName: serverInfo.ServerName,
            version: serverInfo.Version,
            productName: serverInfo.ProductName,
            operatingSystem: serverInfo.OperatingSystem,
            startupWizardCompleted: serverInfo.StartupWizardCompleted || false,
            autoGenerateEmbeddings: false,
        };
        const insertedServers = await connection_1.db
            .insert(schema_1.servers)
            .values(newServer)
            .returning();
        const processingTime = Date.now() - startTime;
        await logJobResult(job.id, "add-server", "completed", insertedServers[0], processingTime);
        return { success: true, server: insertedServers[0] };
    }
    catch (error) {
        const processingTime = Date.now() - startTime;
        await logJobResult(job.id, "add-server", "failed", null, processingTime, error);
        throw error;
    }
}
// Job: Generate embeddings for media items
async function generateMediaEmbeddingsJob(job) {
    const startTime = Date.now();
    const { serverId, itemType = "movies" } = job.data;
    try {
        if (!openai) {
            throw new Error("OpenAI API key not configured");
        }
        console.log(`Generating embeddings for ${itemType} from server ${serverId}`);
        // Get server
        const serverData = await connection_1.db
            .select()
            .from(schema_1.servers)
            .where((0, drizzle_orm_1.eq)(schema_1.servers.id, serverId))
            .limit(1);
        if (!serverData.length) {
            throw new Error(`Server with ID ${serverId} not found`);
        }
        const server = serverData[0];
        // Fetch items from media server
        const response = await axios_1.default.get(`${server.url}/Items`, {
            headers: {
                "X-Emby-Token": server.apiKey,
            },
            params: {
                IncludeItemTypes: itemType === "movies" ? "Movie" : "Series",
                Recursive: true,
                Fields: "Overview,Genres,Tags",
                Limit: 50, // Process in batches
            },
        });
        let processedCount = 0;
        const items = response.data.Items || [];
        for (const item of items) {
            try {
                if (item.Overview) {
                    const textToEmbed = `${item.Name} ${item.Overview} ${(item.Genres || []).join(" ")}`.substring(0, 8000);
                    const embedding = await openai.embeddings.create({
                        model: "text-embedding-ada-002",
                        input: textToEmbed,
                    });
                    // Store as post for now (could be separate media items table)
                    const newPost = {
                        externalId: item.Id,
                        title: item.Name,
                        content: item.Overview,
                        author: itemType,
                        metadata: item,
                        embedding: embedding.data[0].embedding,
                        processed: true,
                    };
                    await connection_1.db.insert(schema_1.posts).values(newPost);
                    processedCount++;
                }
            }
            catch (error) {
                console.error(`Error processing item ${item.Id}:`, error);
            }
        }
        const processingTime = Date.now() - startTime;
        await logJobResult(job.id, "generate-media-embeddings", "completed", { processedCount, itemType }, processingTime);
        return { success: true, processedCount, itemType };
    }
    catch (error) {
        const processingTime = Date.now() - startTime;
        await logJobResult(job.id, "generate-media-embeddings", "failed", null, processingTime, error);
        throw error;
    }
}
// Helper function to sync users
async function syncUsers(serverId, usersData) {
    let syncedCount = 0;
    for (const userData of usersData) {
        try {
            const newUser = {
                id: userData.Id,
                name: userData.Name,
                serverId,
                lastLoginDate: userData.LastLoginDate
                    ? new Date(userData.LastLoginDate)
                    : null,
                lastActivityDate: userData.LastActivityDate
                    ? new Date(userData.LastActivityDate)
                    : null,
                hasPassword: userData.HasPassword || false,
                hasConfiguredPassword: userData.HasConfiguredPassword || false,
                hasConfiguredEasyPassword: userData.HasConfiguredEasyPassword || false,
                enableAutoLogin: userData.Configuration?.EnableAutoLogin || false,
                isAdministrator: userData.Policy?.IsAdministrator || false,
                isHidden: userData.Policy?.IsHidden || false,
                isDisabled: userData.Policy?.IsDisabled || false,
                enableUserPreferenceAccess: userData.Policy?.EnableUserPreferenceAccess !== false,
                enableRemoteControlOfOtherUsers: userData.Policy?.EnableRemoteControlOfOtherUsers || false,
                enableSharedDeviceControl: userData.Policy?.EnableSharedDeviceControl || false,
                enableRemoteAccess: userData.Policy?.EnableRemoteAccess !== false,
                enableLiveTvManagement: userData.Policy?.EnableLiveTvManagement || false,
                enableLiveTvAccess: userData.Policy?.EnableLiveTvAccess !== false,
                enableMediaPlayback: userData.Policy?.EnableMediaPlayback !== false,
                enableAudioPlaybackTranscoding: userData.Policy?.EnableAudioPlaybackTranscoding !== false,
                enableVideoPlaybackTranscoding: userData.Policy?.EnableVideoPlaybackTranscoding !== false,
                enablePlaybackRemuxing: userData.Policy?.EnablePlaybackRemuxing !== false,
                enableContentDeletion: userData.Policy?.EnableContentDeletion || false,
                enableContentDownloading: userData.Policy?.EnableContentDownloading || false,
                enableSyncTranscoding: userData.Policy?.EnableSyncTranscoding !== false,
                enableMediaConversion: userData.Policy?.EnableMediaConversion || false,
                enableAllDevices: userData.Policy?.EnableAllDevices !== false,
                enableAllChannels: userData.Policy?.EnableAllChannels !== false,
                enableAllFolders: userData.Policy?.EnableAllFolders !== false,
                enablePublicSharing: userData.Policy?.EnablePublicSharing || false,
                invalidLoginAttemptCount: userData.Policy?.InvalidLoginAttemptCount || 0,
                loginAttemptsBeforeLockout: userData.Policy?.LoginAttemptsBeforeLockout || 3,
                maxActiveSessions: userData.Policy?.MaxActiveSessions || 0,
                remoteClientBitrateLimit: userData.Policy?.RemoteClientBitrateLimit || 0,
                authenticationProviderId: userData.Policy?.AuthenticationProviderId ||
                    "Jellyfin.Server.Implementations.Users.DefaultAuthenticationProvider",
                passwordResetProviderId: userData.Policy?.PasswordResetProviderId ||
                    "Jellyfin.Server.Implementations.Users.DefaultPasswordResetProvider",
                syncPlayAccess: userData.Policy?.SyncPlayAccess || "CreateAndJoinGroups",
            };
            await connection_1.db.insert(schema_1.users).values(newUser).onConflictDoUpdate({
                target: schema_1.users.id,
                set: newUser,
            });
            syncedCount++;
        }
        catch (error) {
            console.error(`Error syncing user ${userData.Id}:`, error);
        }
    }
    return syncedCount;
}
// Helper function to sync libraries
async function syncLibraries(serverId, librariesData) {
    let syncedCount = 0;
    for (const libraryData of librariesData) {
        try {
            const newLibrary = {
                id: libraryData.ItemId,
                name: libraryData.Name,
                type: libraryData.CollectionType || "mixed",
                serverId,
            };
            await connection_1.db.insert(schema_1.libraries).values(newLibrary).onConflictDoUpdate({
                target: schema_1.libraries.id,
                set: newLibrary,
            });
            syncedCount++;
        }
        catch (error) {
            console.error(`Error syncing library ${libraryData.ItemId}:`, error);
        }
    }
    return syncedCount;
}
// Helper function to sync activities
async function syncActivities(serverId, activitiesData) {
    let syncedCount = 0;
    for (const activityData of activitiesData) {
        try {
            const newActivity = {
                id: activityData.Id.toString(),
                name: activityData.Name,
                shortOverview: activityData.ShortOverview,
                type: activityData.Type,
                date: new Date(activityData.Date),
                severity: activityData.Severity,
                serverId,
                userId: activityData.UserId || null,
                itemId: activityData.ItemId || null,
            };
            await connection_1.db.insert(schema_1.activities).values(newActivity).onConflictDoUpdate({
                target: schema_1.activities.id,
                set: newActivity,
            });
            syncedCount++;
        }
        catch (error) {
            console.error(`Error syncing activity ${activityData.Id}:`, error);
        }
    }
    return syncedCount;
}
// Job: Fetch data from external API
async function fetchExternalDataJob(job) {
    const startTime = Date.now();
    const { url, params } = job.data;
    try {
        console.log(`Fetching data from: ${url}`);
        const response = await axios_1.default.get(url, { params });
        // Save to database
        const newPost = {
            externalId: response.data.id?.toString(),
            title: response.data.title || "No title",
            content: response.data.body || response.data.content,
            author: response.data.author || "Unknown",
            metadata: response.data,
            processed: false,
        };
        const insertedPosts = await connection_1.db.insert(schema_1.posts).values(newPost).returning();
        const processingTime = Date.now() - startTime;
        // Log job result
        await logJobResult(job.id, "fetch-external-data", "completed", insertedPosts[0], processingTime);
        return { success: true, data: insertedPosts[0] };
    }
    catch (error) {
        const processingTime = Date.now() - startTime;
        await logJobResult(job.id, "fetch-external-data", "failed", null, processingTime, error);
        throw error;
    }
}
// Job: Process embeddings for posts
async function generateEmbeddingsJob(job) {
    const startTime = Date.now();
    const { postId } = job.data;
    try {
        if (!openai) {
            throw new Error("OpenAI API key not configured");
        }
        console.log(`Generating embeddings for post ID: ${postId}`);
        // Get post from database
        const post = await connection_1.db
            .select()
            .from(schema_1.posts)
            .where((0, drizzle_orm_1.eq)(schema_1.posts.id, postId))
            .limit(1);
        if (!post.length) {
            throw new Error(`Post with ID ${postId} not found`);
        }
        const postData = post[0];
        const textToEmbed = `${postData.title} ${postData.content}`.substring(0, 8000); // OpenAI limit
        // Generate embedding
        const embedding = await openai.embeddings.create({
            model: "text-embedding-ada-002",
            input: textToEmbed,
        });
        // Update post with embedding
        const updatedPost = await connection_1.db
            .update(schema_1.posts)
            .set({
            embedding: embedding.data[0].embedding,
            processed: true,
        })
            .where((0, drizzle_orm_1.eq)(schema_1.posts.id, postId))
            .returning();
        const processingTime = Date.now() - startTime;
        await logJobResult(job.id, "generate-embeddings", "completed", updatedPost[0], processingTime);
        return { success: true, data: updatedPost[0] };
    }
    catch (error) {
        const processingTime = Date.now() - startTime;
        await logJobResult(job.id, "generate-embeddings", "failed", null, processingTime, error);
        throw error;
    }
}
// Job: Batch process multiple posts
async function batchProcessPostsJob(job) {
    const startTime = Date.now();
    const { limit = 10 } = job.data;
    try {
        console.log(`Batch processing up to ${limit} unprocessed posts`);
        // Get unprocessed posts
        const unprocessedPosts = await connection_1.db
            .select()
            .from(schema_1.posts)
            .where((0, drizzle_orm_1.eq)(schema_1.posts.processed, false))
            .limit(limit);
        const results = [];
        for (const post of unprocessedPosts) {
            try {
                if (openai && post.title && post.content) {
                    const textToEmbed = `${post.title} ${post.content}`.substring(0, 8000);
                    const embedding = await openai.embeddings.create({
                        model: "text-embedding-ada-002",
                        input: textToEmbed,
                    });
                    const updatedPost = await connection_1.db
                        .update(schema_1.posts)
                        .set({
                        embedding: embedding.data[0].embedding,
                        processed: true,
                    })
                        .where((0, drizzle_orm_1.eq)(schema_1.posts.id, post.id))
                        .returning();
                    results.push(updatedPost[0]);
                }
                else {
                    // Mark as processed even if no embedding
                    await connection_1.db
                        .update(schema_1.posts)
                        .set({ processed: true })
                        .where((0, drizzle_orm_1.eq)(schema_1.posts.id, post.id));
                    results.push(post);
                }
            }
            catch (error) {
                console.error(`Error processing post ${post.id}:`, error);
            }
        }
        const processingTime = Date.now() - startTime;
        await logJobResult(job.id, "batch-process-posts", "completed", { processedCount: results.length }, processingTime);
        return { success: true, processedCount: results.length, data: results };
    }
    catch (error) {
        const processingTime = Date.now() - startTime;
        await logJobResult(job.id, "batch-process-posts", "failed", null, processingTime, error);
        throw error;
    }
}
// Job: Custom data processing
async function customProcessingJob(job) {
    const startTime = Date.now();
    const { action, data } = job.data;
    try {
        console.log(`Running custom processing job: ${action}`);
        let result;
        switch (action) {
            case "cleanup-old-data":
                // Example: cleanup logic
                result = { message: "Cleanup completed", action };
                break;
            case "sync-external-data":
                // Example: sync logic
                result = { message: "Sync completed", action };
                break;
            default:
                throw new Error(`Unknown action: ${action}`);
        }
        const processingTime = Date.now() - startTime;
        await logJobResult(job.id, "custom-processing", "completed", result, processingTime);
        return { success: true, data: result };
    }
    catch (error) {
        const processingTime = Date.now() - startTime;
        await logJobResult(job.id, "custom-processing", "failed", null, processingTime, error);
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
        await connection_1.db
            .update(schema_1.servers)
            .set({
            syncStatus: "syncing",
            syncProgress: "users",
            lastSyncStarted: new Date(),
            syncError: null,
        })
            .where((0, drizzle_orm_1.eq)(schema_1.servers.id, serverId));
        // Get server configuration
        const serverData = await connection_1.db
            .select()
            .from(schema_1.servers)
            .where((0, drizzle_orm_1.eq)(schema_1.servers.id, serverId))
            .limit(1);
        if (!serverData.length) {
            throw new Error(`Server with ID ${serverId} not found`);
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
            });
            syncResults.users = await syncUsers(serverId, usersResponse.data);
            console.log(`Synced ${syncResults.users} users`);
        }
        catch (error) {
            console.error("Error syncing users:", error);
            throw new Error(`Failed to sync users: ${error}`);
        }
        // Update progress to libraries
        await connection_1.db
            .update(schema_1.servers)
            .set({ syncProgress: "libraries" })
            .where((0, drizzle_orm_1.eq)(schema_1.servers.id, serverId));
        // Step 2: Sync Libraries
        console.log(`Syncing libraries for server ${serverId}`);
        try {
            const librariesResponse = await axios_1.default.get(`${server.url}/Library/VirtualFolders`, {
                headers: {
                    "X-Emby-Token": server.apiKey,
                    "Content-Type": "application/json",
                },
            });
            syncResults.libraries = await syncLibraries(serverId, librariesResponse.data);
            console.log(`Synced ${syncResults.libraries} libraries`);
        }
        catch (error) {
            console.error("Error syncing libraries:", error);
            throw new Error(`Failed to sync libraries: ${error}`);
        }
        // Update progress to items
        await connection_1.db
            .update(schema_1.servers)
            .set({ syncProgress: "items" })
            .where((0, drizzle_orm_1.eq)(schema_1.servers.id, serverId));
        // Step 3: Sync Items (for each library)
        console.log(`Syncing items for server ${serverId}`);
        try {
            const librariesData = await connection_1.db
                .select()
                .from(schema_1.libraries)
                .where((0, drizzle_orm_1.eq)(schema_1.libraries.serverId, serverId));
            for (const library of librariesData) {
                const itemsResponse = await axios_1.default.get(`${server.url}/Items?ParentId=${library.id}&Recursive=true&Fields=BasicSyncInfo,MediaSourceCount,Path`, {
                    headers: {
                        "X-Emby-Token": server.apiKey,
                        "Content-Type": "application/json",
                    },
                });
                const itemsSynced = await syncItems(serverId, library.id, itemsResponse.data.Items || []);
                syncResults.items += itemsSynced;
                console.log(`Synced ${itemsSynced} items for library ${library.name}`);
            }
            console.log(`Total synced ${syncResults.items} items`);
        }
        catch (error) {
            console.error("Error syncing items:", error);
            throw new Error(`Failed to sync items: ${error instanceof Error ? error.message : String(error)}`);
        }
        // Update progress to activities
        await connection_1.db
            .update(schema_1.servers)
            .set({ syncProgress: "activities" })
            .where((0, drizzle_orm_1.eq)(schema_1.servers.id, serverId));
        // Step 4: Sync Activities
        console.log(`Syncing activities for server ${serverId}`);
        try {
            const activitiesResponse = await axios_1.default.get(`${server.url}/System/ActivityLog/Entries`, {
                headers: {
                    "X-Emby-Token": server.apiKey,
                    "Content-Type": "application/json",
                },
            });
            syncResults.activities = await syncActivities(serverId, activitiesResponse.data.Items || []);
            console.log(`Synced ${syncResults.activities} activities`);
        }
        catch (error) {
            console.error("Error syncing activities:", error);
            throw new Error(`Failed to sync activities: ${error instanceof Error ? error.message : String(error)}`);
        }
        // Update server status to completed
        await connection_1.db
            .update(schema_1.servers)
            .set({
            syncStatus: "completed",
            syncProgress: "completed",
            lastSyncCompleted: new Date(),
        })
            .where((0, drizzle_orm_1.eq)(schema_1.servers.id, serverId));
        const processingTime = Date.now() - startTime;
        await logJobResult(job.id, "sequential-server-sync", "completed", syncResults, processingTime);
        console.log(`Sequential sync completed for server ${serverId}:`, syncResults);
        return { success: true, syncResults };
    }
    catch (error) {
        console.error(`Sequential sync failed for server ${serverId}:`, error);
        // Update server status to failed
        await connection_1.db
            .update(schema_1.servers)
            .set({
            syncStatus: "failed",
            syncError: error instanceof Error ? error.message : String(error),
        })
            .where((0, drizzle_orm_1.eq)(schema_1.servers.id, serverId));
        const processingTime = Date.now() - startTime;
        await logJobResult(job.id, "sequential-server-sync", "failed", null, processingTime, error instanceof Error ? error.message : String(error));
        throw error;
    }
}
// Helper function to sync items
async function syncItems(serverId, libraryId, itemsData) {
    let syncedCount = 0;
    for (const itemData of itemsData) {
        try {
            const newItem = {
                id: itemData.Id,
                serverId,
                libraryId,
                name: itemData.Name || "",
                type: itemData.Type || "",
                originalTitle: itemData.OriginalTitle,
                etag: itemData.Etag,
                dateCreated: itemData.DateCreated
                    ? new Date(itemData.DateCreated)
                    : null,
                container: itemData.Container,
                sortName: itemData.SortName,
                premiereDate: itemData.PremiereDate
                    ? new Date(itemData.PremiereDate)
                    : null,
                path: itemData.Path,
                officialRating: itemData.OfficialRating,
                overview: itemData.Overview,
                communityRating: itemData.CommunityRating,
                runtimeTicks: itemData.RunTimeTicks || 0,
                productionYear: itemData.ProductionYear,
                isFolder: itemData.IsFolder || false,
                parentId: itemData.ParentId,
                mediaType: itemData.MediaType,
                width: itemData.Width,
                height: itemData.Height,
                seriesName: itemData.SeriesName,
                seriesId: itemData.SeriesId,
                seasonId: itemData.SeasonId,
                seasonName: itemData.SeasonName,
                indexNumber: itemData.IndexNumber,
                parentIndexNumber: itemData.ParentIndexNumber,
                videoType: itemData.VideoType,
                hasSubtitles: itemData.HasSubtitles || false,
                channelId: itemData.ChannelId,
                locationType: itemData.LocationType,
                primaryImageAspectRatio: itemData.PrimaryImageAspectRatio,
                primaryImageTag: itemData.ImageTags?.Primary,
                seriesPrimaryImageTag: itemData.SeriesPrimaryImageTag,
                primaryImageThumbTag: itemData.ImageTags?.Thumb,
                primaryImageLogoTag: itemData.ImageTags?.Logo,
                rawData: itemData,
            };
            await connection_1.db.insert(schema_1.items).values(newItem).onConflictDoUpdate({
                target: schema_1.items.id,
                set: newItem,
            });
            syncedCount++;
        }
        catch (error) {
            console.error(`Error syncing item ${itemData.Id}:`, error);
        }
    }
    return syncedCount;
}
// Helper function to log job results
async function logJobResult(jobId, jobName, status, result, processingTime, error) {
    try {
        const jobResult = {
            jobId,
            jobName,
            status,
            result: result ? JSON.parse(JSON.stringify(result)) : null,
            error: error ? error.message || String(error) : null,
            processingTime,
        };
        await connection_1.db.insert(schema_1.jobResults).values(jobResult);
    }
    catch (err) {
        console.error("Failed to log job result:", err);
    }
}
