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
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.JobTypes = void 0;
exports.initializeJobQueue = initializeJobQueue;
exports.getJobQueue = getJobQueue;
exports.stopJobQueue = stopJobQueue;
const pg_boss_1 = __importDefault(require("pg-boss"));
const dotenv = __importStar(require("dotenv"));
const workers_1 = require("./workers");
dotenv.config();
let boss = null;
async function initializeJobQueue() {
    if (boss) {
        return boss;
    }
    boss = new pg_boss_1.default({
        connectionString: process.env.DATABASE_URL,
        retryLimit: 3,
        retryDelay: 30,
        expireInHours: 24,
        deleteAfterHours: 48,
    });
    // Start the boss
    await boss.start();
    // Register job handlers
    await registerJobHandlers(boss);
    console.log("Job queue initialized and handlers registered");
    return boss;
}
async function registerJobHandlers(boss) {
    // Register original job types
    await boss.work("fetch-external-data", { teamSize: 2, teamConcurrency: 2 }, workers_1.fetchExternalDataJob);
    await boss.work("generate-embeddings", { teamSize: 1, teamConcurrency: 1 }, workers_1.generateEmbeddingsJob);
    await boss.work("batch-process-posts", { teamSize: 1, teamConcurrency: 1 }, workers_1.batchProcessPostsJob);
    await boss.work("custom-processing", { teamSize: 2, teamConcurrency: 2 }, workers_1.customProcessingJob);
    // Register new media server job types
    await boss.work("sync-server-data", { teamSize: 2, teamConcurrency: 1 }, // Limited concurrency for API rate limiting
    workers_1.syncServerDataJob);
    await boss.work("add-server", { teamSize: 1, teamConcurrency: 1 }, workers_1.addServerJob);
    await boss.work("generate-media-embeddings", { teamSize: 1, teamConcurrency: 1 }, // Limited for OpenAI rate limiting
    workers_1.generateMediaEmbeddingsJob);
    // Register new sequential server sync job type
    await boss.work("sequential-server-sync", { teamSize: 1, teamConcurrency: 1 }, workers_1.sequentialServerSyncJob);
    // Register Jellyfin sync workers
    await boss.work(workers_1.JELLYFIN_JOB_NAMES.FULL_SYNC, { teamSize: 1, teamConcurrency: 1 }, // Limited concurrency for heavy operations
    workers_1.jellyfinFullSyncWorker);
    await boss.work(workers_1.JELLYFIN_JOB_NAMES.USERS_SYNC, { teamSize: 2, teamConcurrency: 2 }, workers_1.jellyfinUsersSyncWorker);
    await boss.work(workers_1.JELLYFIN_JOB_NAMES.LIBRARIES_SYNC, { teamSize: 2, teamConcurrency: 2 }, workers_1.jellyfinLibrariesSyncWorker);
    await boss.work(workers_1.JELLYFIN_JOB_NAMES.ITEMS_SYNC, { teamSize: 1, teamConcurrency: 1 }, // Limited concurrency for heavy operations
    workers_1.jellyfinItemsSyncWorker);
    await boss.work(workers_1.JELLYFIN_JOB_NAMES.ACTIVITIES_SYNC, { teamSize: 2, teamConcurrency: 2 }, workers_1.jellyfinActivitiesSyncWorker);
    await boss.work(workers_1.JELLYFIN_JOB_NAMES.RECENT_ITEMS_SYNC, { teamSize: 3, teamConcurrency: 3 }, // Higher concurrency for lighter operations
    workers_1.jellyfinRecentItemsSyncWorker);
    await boss.work(workers_1.JELLYFIN_JOB_NAMES.RECENT_ACTIVITIES_SYNC, { teamSize: 3, teamConcurrency: 3 }, // Higher concurrency for lighter operations
    workers_1.jellyfinRecentActivitiesSyncWorker);
}
async function getJobQueue() {
    if (!boss) {
        throw new Error("Job queue not initialized. Call initializeJobQueue() first.");
    }
    return boss;
}
async function stopJobQueue() {
    if (boss) {
        await boss.stop();
        boss = null;
        console.log("Job queue stopped");
    }
}
// Job queue utilities
exports.JobTypes = {
    // Original job types
    FETCH_EXTERNAL_DATA: "fetch-external-data",
    GENERATE_EMBEDDINGS: "generate-embeddings",
    BATCH_PROCESS_POSTS: "batch-process-posts",
    CUSTOM_PROCESSING: "custom-processing",
    // New media server job types
    SYNC_SERVER_DATA: "sync-server-data",
    ADD_SERVER: "add-server",
    GENERATE_MEDIA_EMBEDDINGS: "generate-media-embeddings",
    // New sequential server sync job type
    SEQUENTIAL_SERVER_SYNC: "sequential-server-sync",
};
