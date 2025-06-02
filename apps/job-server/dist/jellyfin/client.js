"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.JellyfinClient = void 0;
const axios_1 = __importDefault(require("axios"));
const bottleneck_1 = __importDefault(require("bottleneck"));
const p_retry_1 = __importDefault(require("p-retry"));
const DEFAULT_ITEM_FIELDS = [
    "DateCreated",
    "Etag",
    "ExternalUrls",
    "Genres",
    "OriginalTitle",
    "Overview",
    "ParentId",
    "Path",
    "PrimaryImageAspectRatio",
    "ProductionYear",
    "SortName",
    "Width",
    "Height",
    "ImageTags",
    "ImageBlurHashes",
    "BackdropImageTags",
    "ParentBackdropImageTags",
    "ParentThumbImageTags",
    "SeriesThumbImageTag",
    "SeriesPrimaryImageTag",
    "Container",
    "PremiereDate",
    "CommunityRating",
    "RunTimeTicks",
    "IsFolder",
    "MediaType",
    "SeriesName",
    "SeriesId",
    "SeasonId",
    "SeasonName",
    "IndexNumber",
    "ParentIndexNumber",
    "VideoType",
    "HasSubtitles",
    "ChannelId",
    "ParentBackdropItemId",
    "ParentThumbItemId",
    "LocationType",
    "People",
];
const DEFAULT_IMAGE_TYPES = "Primary,Backdrop,Banner,Thumb";
class JellyfinClient {
    client;
    limiter;
    config;
    constructor(config) {
        this.config = {
            timeout: 60000,
            rateLimitPerSecond: 10,
            maxRetries: 3,
            ...config,
        };
        this.client = axios_1.default.create({
            baseURL: this.config.baseURL,
            timeout: this.config.timeout,
            headers: {
                "X-Emby-Token": this.config.apiKey,
                "Content-Type": "application/json",
            },
        });
        // Set up rate limiting
        this.limiter = new bottleneck_1.default({
            minTime: 1000 / (this.config.rateLimitPerSecond || 10),
            maxConcurrent: 5,
        });
    }
    async makeRequest(method, url, options = {}) {
        return (0, p_retry_1.default)(async () => {
            const response = await this.limiter.schedule(() => this.client[method](url, method === "get" ? { params: options.params } : options.data, method !== "get" ? { params: options.params } : undefined));
            return response.data;
        }, {
            retries: this.config.maxRetries || 3,
            factor: 2,
            minTimeout: 1000,
            maxTimeout: 10000,
            onFailedAttempt: (error) => {
                console.warn(`Request attempt ${error.attemptNumber} failed. ${error.retriesLeft} retries left.`);
            },
        });
    }
    async getUsers() {
        return this.makeRequest("get", "/Users");
    }
    async getUser(userId) {
        return this.makeRequest("get", `/Users/${userId}`);
    }
    async getLibraries() {
        const response = await this.makeRequest("get", "/Library/MediaFolders");
        // Filter out boxsets and playlists like in the Elixir code
        return response.Items.filter((library) => !["boxsets", "playlists"].includes(library.CollectionType || ""));
    }
    async getItem(itemId) {
        return this.makeRequest("get", `/Items/${itemId}`, {
            params: {
                Fields: DEFAULT_ITEM_FIELDS.join(","),
                EnableImageTypes: DEFAULT_IMAGE_TYPES,
            },
        });
    }
    async getLibraryId(itemId) {
        // First get all libraries to compare against
        const libraries = await this.getLibraries();
        const libraryIds = new Set(libraries.map((lib) => lib.Id));
        return this.findLibraryRecursive(itemId, libraryIds);
    }
    async findLibraryRecursive(itemId, libraryIds) {
        const response = await this.makeRequest("get", "/Items", {
            params: {
                Fields: "ParentId",
                ids: itemId,
            },
        });
        if (!response.Items.length) {
            throw new Error(`Item not found: ${itemId}`);
        }
        const item = response.Items[0];
        // Check if current item is a library we know about
        if (libraryIds.has(item.Id)) {
            return item.Id;
        }
        // Not a library - check if it has a parent
        if (!item.ParentId) {
            throw new Error("Reached root item without finding a library match");
        }
        // Continue up the hierarchy
        return this.findLibraryRecursive(item.ParentId, libraryIds);
    }
    async getRecentlyAddedItems(limit = 20) {
        const response = await this.makeRequest("get", "/Items", {
            params: {
                SortBy: "DateCreated",
                SortOrder: "Descending",
                Recursive: "true",
                Fields: DEFAULT_ITEM_FIELDS.join(","),
                ImageTypeLimit: "1",
                EnableImageTypes: DEFAULT_IMAGE_TYPES,
                Limit: limit.toString(),
            },
        });
        return response.Items;
    }
    async getRecentlyAddedItemsByLibrary(libraryId, limit = 20) {
        const response = await this.makeRequest("get", "/Items", {
            params: {
                SortBy: "DateCreated",
                SortOrder: "Descending",
                Recursive: "true",
                ParentId: libraryId,
                Fields: DEFAULT_ITEM_FIELDS.join(","),
                ImageTypeLimit: "1",
                EnableImageTypes: DEFAULT_IMAGE_TYPES,
                Limit: limit.toString(),
            },
        });
        return response.Items;
    }
    async getItemsPage(libraryId, startIndex, limit, imageTypes) {
        const params = {
            ParentId: libraryId,
            Recursive: true,
            Fields: DEFAULT_ITEM_FIELDS.join(","),
            StartIndex: startIndex,
            Limit: limit,
            EnableImageTypes: DEFAULT_IMAGE_TYPES,
            IsFolder: false,
            IsPlaceHolder: false,
        };
        if (imageTypes) {
            params.ImageTypes = Array.isArray(imageTypes)
                ? imageTypes.join(",")
                : imageTypes;
        }
        const response = await this.makeRequest("get", "/Items", {
            params,
        });
        return {
            items: response.Items || [],
            totalCount: response.TotalRecordCount || 0,
        };
    }
    async getItemsWithImages(libraryId, startIndex, limit, imageTypes = ["Primary", "Thumb", "Backdrop"]) {
        return this.getItemsPage(libraryId, startIndex, limit, imageTypes);
    }
    async getActivities(startIndex, limit) {
        const response = await this.makeRequest("get", "/System/ActivityLog/Entries", {
            params: {
                startIndex,
                limit,
            },
        });
        return response.Items;
    }
    async getInstalledPlugins() {
        return this.makeRequest("get", "/Plugins");
    }
    async getSessions() {
        return this.makeRequest("get", "/Sessions");
    }
    // Helper method to create client from server configuration
    static fromServer(server) {
        return new JellyfinClient({
            baseURL: server.url,
            apiKey: server.apiKey,
        });
    }
}
exports.JellyfinClient = JellyfinClient;
