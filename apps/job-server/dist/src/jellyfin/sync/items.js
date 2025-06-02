"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.syncItems = syncItems;
exports.syncRecentlyAddedItems = syncRecentlyAddedItems;
const drizzle_orm_1 = require("drizzle-orm");
const connection_1 = require("../../db/connection");
const schema_1 = require("../../db/schema");
const client_1 = require("../client");
const sync_metrics_1 = require("../sync-metrics");
const p_map_1 = __importDefault(require("p-map"));
const p_limit_1 = __importDefault(require("p-limit"));
async function syncItems(server, options = {}) {
    const { itemPageSize = 500, batchSize = 1000, maxLibraryConcurrency = 2, itemConcurrency = 10, apiRequestDelayMs = 100, } = options;
    const metrics = new sync_metrics_1.SyncMetricsTracker();
    const client = client_1.JellyfinClient.fromServer(server);
    const errors = [];
    try {
        console.log(`Starting items sync for server ${server.name}`);
        // Get all libraries for this server
        const serverLibraries = await connection_1.db
            .select()
            .from(schema_1.libraries)
            .where((0, drizzle_orm_1.eq)(schema_1.libraries.serverId, server.id));
        console.log(`Found ${serverLibraries.length} libraries to sync`);
        // Process libraries with limited concurrency
        const libraryLimit = (0, p_limit_1.default)(maxLibraryConcurrency);
        await Promise.all(serverLibraries.map((library) => libraryLimit(async () => {
            try {
                console.log(`Starting sync for library: ${library.name} (${library.id})`);
                await syncLibraryItems(library.id, client, metrics, {
                    itemPageSize,
                    batchSize,
                    itemConcurrency,
                    apiRequestDelayMs,
                });
                metrics.incrementLibrariesProcessed();
                console.log(`Completed sync for library: ${library.name}`);
            }
            catch (error) {
                console.error(`Error syncing library ${library.name}:`, error);
                metrics.incrementErrors();
                errors.push(`Library ${library.name}: ${error instanceof Error ? error.message : "Unknown error"}`);
            }
        })));
        const finalMetrics = metrics.finish();
        const data = {
            librariesProcessed: finalMetrics.librariesProcessed,
            itemsProcessed: finalMetrics.itemsProcessed,
            itemsInserted: finalMetrics.itemsInserted,
            itemsUpdated: finalMetrics.itemsUpdated,
            itemsUnchanged: finalMetrics.itemsUnchanged,
        };
        console.log(`Items sync completed for server ${server.name}:`, data);
        if (errors.length > 0) {
            return (0, sync_metrics_1.createSyncResult)("partial", data, finalMetrics, undefined, errors);
        }
        return (0, sync_metrics_1.createSyncResult)("success", data, finalMetrics);
    }
    catch (error) {
        console.error(`Items sync failed for server ${server.name}:`, error);
        const finalMetrics = metrics.finish();
        const errorData = {
            librariesProcessed: finalMetrics.librariesProcessed,
            itemsProcessed: finalMetrics.itemsProcessed,
            itemsInserted: finalMetrics.itemsInserted,
            itemsUpdated: finalMetrics.itemsUpdated,
            itemsUnchanged: finalMetrics.itemsUnchanged,
        };
        return (0, sync_metrics_1.createSyncResult)("error", errorData, finalMetrics, error instanceof Error ? error.message : "Unknown error");
    }
}
async function syncLibraryItems(libraryId, client, metrics, options) {
    let startIndex = 0;
    let hasMoreItems = true;
    while (hasMoreItems) {
        // Add delay between API requests
        if (startIndex > 0) {
            await new Promise((resolve) => setTimeout(resolve, options.apiRequestDelayMs));
        }
        console.log(`Fetching items ${startIndex} to ${startIndex + options.itemPageSize} for library ${libraryId}`);
        try {
            metrics.incrementApiRequests();
            const { items: jellyfinItems, totalCount } = await client.getItemsPage(libraryId, startIndex, options.itemPageSize);
            console.log(`Fetched ${jellyfinItems.length} items from Jellyfin (${startIndex + jellyfinItems.length}/${totalCount})`);
            // Process items in smaller batches to avoid overwhelming the database
            await (0, p_map_1.default)(jellyfinItems, async (jellyfinItem) => {
                try {
                    await processItem(jellyfinItem, libraryId, metrics);
                }
                catch (error) {
                    console.error(`Error processing item ${jellyfinItem.Id}:`, error);
                    metrics.incrementErrors();
                }
            }, { concurrency: options.itemConcurrency });
            startIndex += jellyfinItems.length;
            hasMoreItems = startIndex < totalCount && jellyfinItems.length > 0;
            console.log(`Processed batch for library ${libraryId}: ${startIndex}/${totalCount} items`);
        }
        catch (error) {
            console.error(`Error fetching items page for library ${libraryId}:`, error);
            metrics.incrementErrors();
            break; // Stop processing this library on API error
        }
    }
}
async function processItem(jellyfinItem, libraryId, metrics) {
    // Check if item already exists and compare etag for changes
    const existingItem = await connection_1.db
        .select({ etag: schema_1.items.etag })
        .from(schema_1.items)
        .where((0, drizzle_orm_1.eq)(schema_1.items.id, jellyfinItem.Id))
        .limit(1);
    const isNewItem = existingItem.length === 0;
    const hasChanged = !isNewItem && existingItem[0].etag !== jellyfinItem.Etag;
    if (!isNewItem && !hasChanged) {
        metrics.incrementItemsUnchanged();
        metrics.incrementItemsProcessed();
        return; // Skip if item hasn't changed
    }
    const itemData = {
        id: jellyfinItem.Id,
        serverId: await getServerIdFromLibrary(libraryId),
        libraryId,
        name: jellyfinItem.Name,
        type: jellyfinItem.Type,
        originalTitle: jellyfinItem.OriginalTitle || null,
        etag: jellyfinItem.Etag || null,
        dateCreated: jellyfinItem.DateCreated
            ? new Date(jellyfinItem.DateCreated)
            : null,
        container: jellyfinItem.Container || null,
        sortName: jellyfinItem.SortName || null,
        premiereDate: jellyfinItem.PremiereDate
            ? new Date(jellyfinItem.PremiereDate)
            : null,
        path: jellyfinItem.Path || null,
        officialRating: jellyfinItem.OfficialRating || null,
        overview: jellyfinItem.Overview || null,
        communityRating: jellyfinItem.CommunityRating || null,
        runtimeTicks: jellyfinItem.RunTimeTicks || null,
        productionYear: jellyfinItem.ProductionYear || null,
        isFolder: jellyfinItem.IsFolder,
        parentId: jellyfinItem.ParentId || null,
        mediaType: jellyfinItem.MediaType || null,
        width: jellyfinItem.Width || null,
        height: jellyfinItem.Height || null,
        seriesName: jellyfinItem.SeriesName || null,
        seriesId: jellyfinItem.SeriesId || null,
        seasonId: jellyfinItem.SeasonId || null,
        seasonName: jellyfinItem.SeasonName || null,
        indexNumber: jellyfinItem.IndexNumber || null,
        parentIndexNumber: jellyfinItem.ParentIndexNumber || null,
        videoType: jellyfinItem.VideoType || null,
        hasSubtitles: jellyfinItem.HasSubtitles || false,
        channelId: jellyfinItem.ChannelId || null,
        locationType: jellyfinItem.LocationType,
        primaryImageAspectRatio: jellyfinItem.PrimaryImageAspectRatio || null,
        primaryImageTag: jellyfinItem.ImageTags?.Primary || null,
        seriesPrimaryImageTag: jellyfinItem.SeriesPrimaryImageTag || null,
        primaryImageThumbTag: jellyfinItem.ParentThumbImageTag || null,
        primaryImageLogoTag: jellyfinItem.ParentLogoImageTag || null,
        rawData: jellyfinItem, // Store complete BaseItemDto
        updatedAt: new Date(),
    };
    // Upsert item
    await connection_1.db
        .insert(schema_1.items)
        .values(itemData)
        .onConflictDoUpdate({
        target: schema_1.items.id,
        set: {
            ...itemData,
            updatedAt: new Date(),
        },
    });
    metrics.incrementDatabaseOperations();
    if (isNewItem) {
        metrics.incrementItemsInserted();
    }
    else {
        metrics.incrementItemsUpdated();
    }
    metrics.incrementItemsProcessed();
}
// Cache for server ID lookups
const serverIdCache = new Map();
async function getServerIdFromLibrary(libraryId) {
    if (serverIdCache.has(libraryId)) {
        return serverIdCache.get(libraryId);
    }
    const library = await connection_1.db
        .select({ serverId: schema_1.libraries.serverId })
        .from(schema_1.libraries)
        .where((0, drizzle_orm_1.eq)(schema_1.libraries.id, libraryId))
        .limit(1);
    if (library.length === 0) {
        throw new Error(`Library not found: ${libraryId}`);
    }
    const serverId = library[0].serverId;
    serverIdCache.set(libraryId, serverId);
    return serverId;
}
async function syncRecentlyAddedItems(server, limit = 100) {
    const metrics = new sync_metrics_1.SyncMetricsTracker();
    const client = client_1.JellyfinClient.fromServer(server);
    const errors = [];
    try {
        console.log(`Starting recently added items sync for server ${server.name} (limit: ${limit})`);
        // Get all libraries for this server (that haven't been removed)
        const serverLibraries = await connection_1.db
            .select()
            .from(schema_1.libraries)
            .where((0, drizzle_orm_1.eq)(schema_1.libraries.serverId, server.id));
        console.log(`Found ${serverLibraries.length} libraries to sync`);
        let allMappedItems = [];
        let allInvalidItems = [];
        // Collect recent items from all libraries with their already-known library IDs
        for (const library of serverLibraries) {
            try {
                console.log(`Fetching recently added items from library: ${library.name} (limit: ${limit})`);
                metrics.incrementApiRequests();
                const libraryItems = await client.getRecentlyAddedItemsByLibrary(library.id, limit);
                metrics.incrementItemsProcessed(libraryItems.length);
                console.log(`Retrieved ${libraryItems.length} recently added items from library ${library.name}`);
                // Map items, knowing they belong to the current library
                const { validItems, invalidItems } = await mapItemsWithKnownLibrary(libraryItems, library.id, server.id);
                allMappedItems = allMappedItems.concat(validItems);
                allInvalidItems = allInvalidItems.concat(invalidItems);
            }
            catch (error) {
                console.error(`API error when fetching items from library ${library.name}:`, error);
                metrics.incrementErrors();
                errors.push(`Library ${library.name}: ${error instanceof Error ? error.message : "Unknown error"}`);
            }
        }
        console.log(`Total recently added items collected: ${allMappedItems.length}`);
        if (allMappedItems.length === 0) {
            console.log("No recently added items found across libraries");
            const finalMetrics = metrics.finish();
            const data = {
                librariesProcessed: serverLibraries.length,
                itemsProcessed: finalMetrics.itemsProcessed,
                itemsInserted: 0,
                itemsUpdated: 0,
                itemsUnchanged: 0,
            };
            return (0, sync_metrics_1.createSyncResult)("success", data, finalMetrics);
        }
        // Process valid items - determine inserts vs updates
        metrics.incrementDatabaseOperations();
        const { insertResult, updateResult, unchangedCount } = await processValidItems(allMappedItems, allInvalidItems, server.id);
        const finalMetrics = metrics.finish();
        const data = {
            librariesProcessed: serverLibraries.length,
            itemsProcessed: finalMetrics.itemsProcessed,
            itemsInserted: insertResult,
            itemsUpdated: updateResult,
            itemsUnchanged: unchangedCount,
        };
        console.log(`Recently added items sync completed for server ${server.name}:`, data);
        if (allInvalidItems.length > 0 || errors.length > 0) {
            const allErrors = errors.concat(allInvalidItems.map((item) => `Item ${item.id}: ${item.error}`));
            return (0, sync_metrics_1.createSyncResult)("partial", data, finalMetrics, undefined, allErrors);
        }
        return (0, sync_metrics_1.createSyncResult)("success", data, finalMetrics);
    }
    catch (error) {
        console.error(`Recently added items sync failed for server ${server.name}:`, error);
        const finalMetrics = metrics.finish();
        const errorData = {
            librariesProcessed: 0,
            itemsProcessed: finalMetrics.itemsProcessed,
            itemsInserted: 0,
            itemsUpdated: 0,
            itemsUnchanged: 0,
        };
        return (0, sync_metrics_1.createSyncResult)("error", errorData, finalMetrics, error instanceof Error ? error.message : "Unknown error");
    }
}
/**
 * Map Jellyfin items to our format with known library context
 */
async function mapItemsWithKnownLibrary(items, libraryId, serverId) {
    const validItems = [];
    const invalidItems = [];
    for (const item of items) {
        try {
            // We already know the library_id since we fetched per library
            const mappedItem = mapJellyfinItem(item, libraryId, serverId);
            validItems.push(mappedItem);
        }
        catch (error) {
            // Catch any mapping errors
            console.error(`Error mapping item ${item.Id}:`, error);
            invalidItems.push({
                id: item.Id,
                error: error instanceof Error ? error.message : "Unknown error",
            });
        }
    }
    return { validItems, invalidItems };
}
/**
 * Map a single Jellyfin item to our database format
 */
function mapJellyfinItem(jellyfinItem, libraryId, serverId) {
    return {
        id: jellyfinItem.Id,
        serverId,
        libraryId,
        name: jellyfinItem.Name,
        type: jellyfinItem.Type,
        originalTitle: jellyfinItem.OriginalTitle || null,
        etag: jellyfinItem.Etag || null,
        dateCreated: jellyfinItem.DateCreated
            ? new Date(jellyfinItem.DateCreated)
            : null,
        container: jellyfinItem.Container || null,
        sortName: jellyfinItem.SortName || null,
        premiereDate: jellyfinItem.PremiereDate
            ? new Date(jellyfinItem.PremiereDate)
            : null,
        path: jellyfinItem.Path || null,
        officialRating: jellyfinItem.OfficialRating || null,
        overview: jellyfinItem.Overview || null,
        communityRating: jellyfinItem.CommunityRating || null,
        runtimeTicks: jellyfinItem.RunTimeTicks || null,
        productionYear: jellyfinItem.ProductionYear || null,
        isFolder: jellyfinItem.IsFolder,
        parentId: jellyfinItem.ParentId || null,
        mediaType: jellyfinItem.MediaType || null,
        width: jellyfinItem.Width || null,
        height: jellyfinItem.Height || null,
        seriesName: jellyfinItem.SeriesName || null,
        seriesId: jellyfinItem.SeriesId || null,
        seasonId: jellyfinItem.SeasonId || null,
        seasonName: jellyfinItem.SeasonName || null,
        indexNumber: jellyfinItem.IndexNumber || null,
        parentIndexNumber: jellyfinItem.ParentIndexNumber || null,
        videoType: jellyfinItem.VideoType || null,
        hasSubtitles: jellyfinItem.HasSubtitles || false,
        channelId: jellyfinItem.ChannelId || null,
        locationType: jellyfinItem.LocationType,
        primaryImageAspectRatio: jellyfinItem.PrimaryImageAspectRatio || null,
        primaryImageTag: jellyfinItem.ImageTags?.Primary || null,
        seriesPrimaryImageTag: jellyfinItem.SeriesPrimaryImageTag || null,
        primaryImageThumbTag: jellyfinItem.ParentThumbImageTag || null,
        primaryImageLogoTag: jellyfinItem.ParentLogoImageTag || null,
        rawData: jellyfinItem, // Store complete BaseItemDto
        updatedAt: new Date(),
    };
}
/**
 * Process valid items - separate into inserts and updates based on detailed field comparison
 */
async function processValidItems(validItems, invalidItems, serverId) {
    // Fields that we track for changes (matching the Elixir version)
    const trackedFields = [
        "name",
        "originalTitle",
        "etag",
        "container",
        "sortName",
        "premiereDate",
        "path",
        "officialRating",
        "overview",
        "communityRating",
        "runtimeTicks",
        "productionYear",
        "isFolder",
        "parentId",
        "mediaType",
        "width",
        "height",
        "seriesName",
        "seriesId",
        "seasonId",
        "seasonName",
        "indexNumber",
        "parentIndexNumber",
        "primaryImageAspectRatio",
        "primaryImageTag",
        "seriesPrimaryImageTag",
        "primaryImageThumbTag",
        "primaryImageLogoTag",
        "videoType",
        "hasSubtitles",
        "channelId",
        "locationType",
    ];
    // Fetch existing items with all fields to compare
    const jellyfinIds = validItems.map((item) => item.id);
    const existingItems = await connection_1.db
        .select()
        .from(schema_1.items)
        .where((0, drizzle_orm_1.and)((0, drizzle_orm_1.inArray)(schema_1.items.id, jellyfinIds), (0, drizzle_orm_1.eq)(schema_1.items.serverId, serverId)));
    const existingMap = new Map(existingItems.map((item) => [item.id, item]));
    // Separate items into inserts, updates, and unchanged
    const itemsToInsert = [];
    const itemsToUpdate = [];
    const unchangedItems = [];
    for (const item of validItems) {
        const existing = existingMap.get(item.id);
        if (!existing) {
            // New item, add to inserts
            itemsToInsert.push(item);
        }
        else {
            // Check if any tracked field has changed or if images have changed
            const fieldsChanged = hasFieldsChanged(existing, item, trackedFields);
            const imagesChanged = hasImageFieldsChanged(existing, item);
            if (fieldsChanged || imagesChanged) {
                // If only images changed, log it
                if (!fieldsChanged && imagesChanged) {
                    console.log(`Image update detected for item ${item.id}`);
                }
                itemsToUpdate.push(item);
            }
            else {
                unchangedItems.push(item);
            }
        }
    }
    // Process insertions and updates
    const insertResult = await processInserts(itemsToInsert);
    const updateResult = await processUpdates(itemsToUpdate, trackedFields);
    const unchangedCount = unchangedItems.length;
    return { insertResult, updateResult, unchangedCount };
}
/**
 * Check if any tracked fields have changed between existing and new item
 */
function hasFieldsChanged(existing, newItem, trackedFields) {
    for (const field of trackedFields) {
        const existingValue = existing[field];
        const newValue = newItem[field];
        // Handle dates specially
        if (existingValue instanceof Date && newValue instanceof Date) {
            if (existingValue.getTime() !== newValue.getTime()) {
                return true;
            }
        }
        else if (existingValue !== newValue) {
            return true;
        }
    }
    return false;
}
/**
 * Check if image-related fields have changed
 */
function hasImageFieldsChanged(existing, newItem) {
    const imageFields = [
        "primaryImageTag",
        "seriesPrimaryImageTag",
        "primaryImageThumbTag",
        "primaryImageLogoTag",
        "primaryImageAspectRatio",
    ];
    for (const field of imageFields) {
        if (existing[field] !== newItem[field]) {
            return true;
        }
    }
    // Also check rawData for backdrop image tags and image blur hashes
    const existingRaw = existing.rawData || {};
    const newRaw = newItem.rawData || {};
    if (JSON.stringify(existingRaw.BackdropImageTags) !==
        JSON.stringify(newRaw.BackdropImageTags)) {
        return true;
    }
    if (JSON.stringify(existingRaw.ImageBlurHashes) !==
        JSON.stringify(newRaw.ImageBlurHashes)) {
        return true;
    }
    return false;
}
/**
 * Insert new items
 */
async function processInserts(itemsToInsert) {
    if (itemsToInsert.length === 0)
        return 0;
    try {
        await connection_1.db.insert(schema_1.items).values(itemsToInsert);
        console.log(`Inserted ${itemsToInsert.length} new items`);
        return itemsToInsert.length;
    }
    catch (error) {
        console.error("Error inserting items:", error);
        throw error;
    }
}
/**
 * Update changed items
 */
async function processUpdates(itemsToUpdate, trackedFields) {
    if (itemsToUpdate.length === 0)
        return 0;
    let updateCount = 0;
    for (const item of itemsToUpdate) {
        try {
            // Convert item to update fields
            const updateFields = {};
            for (const field of trackedFields) {
                if (field in item) {
                    const value = item[field];
                    if (value !== undefined) {
                        updateFields[field] = value;
                    }
                }
            }
            updateFields.updatedAt = new Date();
            await connection_1.db
                .update(schema_1.items)
                .set(updateFields)
                .where((0, drizzle_orm_1.and)((0, drizzle_orm_1.eq)(schema_1.items.id, item.id), (0, drizzle_orm_1.eq)(schema_1.items.serverId, item.serverId)));
            updateCount++;
        }
        catch (error) {
            console.error(`Error updating item ${item.id}:`, error);
            // Continue with other items rather than failing the whole batch
        }
    }
    console.log(`Updated ${updateCount} items`);
    return updateCount;
}
