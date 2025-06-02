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
const express_1 = __importDefault(require("express"));
const cors_1 = __importDefault(require("cors"));
const helmet_1 = __importDefault(require("helmet"));
const dotenv = __importStar(require("dotenv"));
const queue_1 = require("./jobs/queue");
const scheduler_1 = require("./jobs/scheduler");
const session_poller_1 = require("./jobs/session-poller");
const database_1 = require("@streamystats/database");
const jobs_1 = __importDefault(require("./routes/jobs"));
// Load environment variables
dotenv.config();
const app = (0, express_1.default)();
const PORT = process.env.PORT || 3000;
// Middleware
app.use((0, helmet_1.default)());
app.use((0, cors_1.default)());
app.use(express_1.default.json({ limit: "10mb" }));
app.use(express_1.default.urlencoded({ extended: true }));
// Routes
app.use("/api/jobs", jobs_1.default);
// Health check endpoint
app.get("/health", (req, res) => {
    res.json({
        status: "ok",
        timestamp: new Date().toISOString(),
        uptime: process.uptime(),
        scheduler: scheduler_1.activityScheduler.getStatus(),
        sessionPoller: session_poller_1.sessionPoller.getStatus(),
    });
});
// Root endpoint
app.get("/", (req, res) => {
    res.json({
        message: "Job Server API",
        version: "1.0.0",
        endpoints: {
            health: "/health",
            jobs: "/api/jobs",
            queueStats: "/api/jobs/queue/stats",
            jobResults: "/api/jobs/results",
            serverStatus: "/api/jobs/server-status",
        },
    });
});
// Error handling middleware
app.use((err, req, res, next) => {
    console.error("Error:", err);
    res.status(500).json({
        error: "Internal server error",
        message: process.env.NODE_ENV === "development"
            ? err.message
            : "Something went wrong",
    });
});
// 404 handler
app.use("*", (req, res) => {
    res.status(404).json({ error: "Route not found" });
});
async function startServer() {
    try {
        // Initialize job queue
        console.log("Initializing job queue...");
        await (0, queue_1.getJobQueue)();
        // Start the sync scheduler
        console.log("Starting sync scheduler...");
        await scheduler_1.activityScheduler.start();
        // Start the session poller
        console.log("Starting session poller...");
        await session_poller_1.sessionPoller.start();
        // Start the server
        app.listen(PORT, () => {
            console.log(`🚀 Job server running on port ${PORT}`);
            console.log(`📊 Health check: http://localhost:${PORT}/health`);
            console.log(`🔧 API docs: http://localhost:${PORT}/`);
            const status = scheduler_1.activityScheduler.getStatus();
            console.log(`⏰ Activity sync scheduler is running (${status.activitySyncInterval})`);
            console.log(`📦 Recently added items sync scheduler is running (${status.recentItemsSyncInterval})`);
            console.log(`🎯 Session poller is running (every 5 seconds)`);
        });
    }
    catch (error) {
        console.error("Failed to start server:", error);
        process.exit(1);
    }
}
// Graceful shutdown
process.on("SIGTERM", async () => {
    console.log("Received SIGTERM, shutting down gracefully...");
    scheduler_1.activityScheduler.stop();
    session_poller_1.sessionPoller.stop();
    await (0, queue_1.closeJobQueue)();
    await (0, database_1.closeConnection)();
    process.exit(0);
});
process.on("SIGINT", async () => {
    console.log("Received SIGINT, shutting down gracefully...");
    scheduler_1.activityScheduler.stop();
    session_poller_1.sessionPoller.stop();
    await (0, queue_1.closeJobQueue)();
    await (0, database_1.closeConnection)();
    process.exit(0);
});
// Start the server
startServer();
