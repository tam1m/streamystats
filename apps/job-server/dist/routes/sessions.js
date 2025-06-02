"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = __importDefault(require("express"));
const session_poller_1 = require("../jobs/session-poller");
const router = express_1.default.Router();
/**
 * Get active sessions for a specific server
 */
router.get("/active/:serverId", (req, res) => {
    try {
        const serverId = parseInt(req.params.serverId);
        if (isNaN(serverId)) {
            return res.status(400).json({ error: "Invalid server ID" });
        }
        const activeSessions = session_poller_1.sessionPoller.getActiveSessions(serverId);
        res.json({
            serverId,
            activeSessions,
            count: activeSessions.length,
        });
    }
    catch (error) {
        console.error("Error getting active sessions:", error);
        res.status(500).json({ error: "Failed to get active sessions" });
    }
});
/**
 * Get session poller status
 */
router.get("/poller/status", (req, res) => {
    try {
        const status = session_poller_1.sessionPoller.getStatus();
        res.json(status);
    }
    catch (error) {
        console.error("Error getting session poller status:", error);
        res.status(500).json({ error: "Failed to get session poller status" });
    }
});
/**
 * Update session poller configuration
 */
router.post("/poller/config", (req, res) => {
    try {
        const { intervalMs, enabled } = req.body;
        const config = {};
        if (typeof intervalMs === "number")
            config.intervalMs = intervalMs;
        if (typeof enabled === "boolean")
            config.enabled = enabled;
        session_poller_1.sessionPoller.updateConfig(config);
        res.json({
            message: "Session poller configuration updated",
            newStatus: session_poller_1.sessionPoller.getStatus(),
        });
    }
    catch (error) {
        console.error("Error updating session poller config:", error);
        res
            .status(500)
            .json({ error: "Failed to update session poller configuration" });
    }
});
/**
 * Start session poller
 */
router.post("/poller/start", async (req, res) => {
    try {
        await session_poller_1.sessionPoller.start();
        res.json({
            message: "Session poller started",
            status: session_poller_1.sessionPoller.getStatus(),
        });
    }
    catch (error) {
        console.error("Error starting session poller:", error);
        res.status(500).json({ error: "Failed to start session poller" });
    }
});
/**
 * Stop session poller
 */
router.post("/poller/stop", (req, res) => {
    try {
        session_poller_1.sessionPoller.stop();
        res.json({
            message: "Session poller stopped",
            status: session_poller_1.sessionPoller.getStatus(),
        });
    }
    catch (error) {
        console.error("Error stopping session poller:", error);
        res.status(500).json({ error: "Failed to stop session poller" });
    }
});
exports.default = router;
