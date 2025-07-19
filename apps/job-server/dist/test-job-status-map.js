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
Object.defineProperty(exports, "__esModule", { value: true });
const dotenv = __importStar(require("dotenv"));
const queue_1 = require("./jobs/queue");
// Load environment variables
dotenv.config();
async function testJobStatusInServerStatus() {
    try {
        console.log("🧪 Testing Simple Job Status Map in Server Status Endpoint");
        console.log("==========================================================");
        // Initialize job queue
        console.log("📦 Initializing job queue...");
        await (0, queue_1.getJobQueue)();
        // Test the endpoint by making a direct HTTP request
        const baseUrl = process.env.JOB_SERVER_URL || "http://localhost:3005";
        const url = `${baseUrl}/api/jobs/server-status`;
        console.log(`🌐 Testing endpoint: ${url}`);
        try {
            const response = await fetch(url);
            if (!response.ok) {
                throw new Error(`HTTP ${response.status}: ${response.statusText}`);
            }
            const data = (await response.json());
            console.log("\n✅ Endpoint Response:");
            console.log(`Timestamp: ${data.timestamp}`);
            console.log(`Uptime: ${Math.round(data.uptime)}s`);
            // Test simple job status map
            if (data.jobStatusMap && typeof data.jobStatusMap === "object") {
                console.log("\n📊 Simple Job Status Map:");
                const jobEntries = Object.entries(data.jobStatusMap);
                console.log(`  Total jobs: ${jobEntries.length}`);
                // Count by status
                const statusCounts = {
                    processing: 0,
                    completed: 0,
                    failed: 0,
                };
                jobEntries.forEach(([jobName, status]) => {
                    if (status in statusCounts) {
                        statusCounts[status]++;
                    }
                });
                console.log(`  Processing: ${statusCounts.processing}`);
                console.log(`  Completed: ${statusCounts.completed}`);
                console.log(`  Failed: ${statusCounts.failed}`);
                console.log("\n📋 Sample Jobs:");
                jobEntries.slice(0, 5).forEach(([jobName, status]) => {
                    console.log(`  ${jobName}: ${status}`);
                });
                if (jobEntries.length > 5) {
                    console.log(`  ... and ${jobEntries.length - 5} more jobs`);
                }
            }
            else {
                console.log("❌ Job status map not found or invalid in response");
            }
            // Also test other server status sections
            console.log("\n📊 Queue Stats:");
            console.log(`  Total queued: ${data.queueStats?.totalQueued || 0}`);
            console.log("\n🖥️ System Health:");
            console.log(`  Overall: ${data.systemHealth?.overall || "unknown"}`);
            console.log(`  Issues: ${data.systemHealth?.issues?.length || 0}`);
            console.log(`  Warnings: ${data.systemHealth?.warnings?.length || 0}`);
            console.log("\n✅ Test completed successfully!");
        }
        catch (fetchError) {
            console.error("❌ Failed to fetch from endpoint:", fetchError);
            console.log("💡 Make sure the job server is running on the correct port");
        }
    }
    catch (error) {
        console.error("❌ Test failed:", error);
    }
    finally {
        // Cleanup
        console.log("\n🧹 Cleaning up...");
        await (0, queue_1.closeJobQueue)();
        process.exit(0);
    }
}
// Run the test
testJobStatusInServerStatus();
