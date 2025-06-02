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
const database_1 = require("@streamystats/database");
const scheduler_1 = require("./jobs/scheduler");
const queue_1 = require("./jobs/queue");
// Load environment variables
dotenv.config();
async function testPeriodicSync() {
    try {
        console.log("🧪 Testing Periodic Activity Sync");
        console.log("================================");
        // Initialize job queue
        console.log("📦 Initializing job queue...");
        await (0, queue_1.getJobQueue)();
        // Get all servers
        console.log("🔍 Fetching servers...");
        const allServers = await database_1.db.select().from(database_1.servers);
        console.log(`Found ${allServers.length} servers:`);
        allServers.forEach((server, index) => {
            console.log(`  ${index + 1}. ${server.name} (ID: ${server.id}) - Status: ${server.syncStatus}`);
        });
        if (allServers.length === 0) {
            console.log("❌ No servers found. Please add a server first.");
            return;
        }
        // Test scheduler status
        console.log("\n📊 Scheduler Status:");
        const status = scheduler_1.activityScheduler.getStatus();
        console.log(`  Enabled: ${status.enabled}`);
        console.log(`  Interval: ${status.activitySyncInterval}`);
        console.log(`  Running tasks: ${status.runningTasks.join(", ") || "None"}`);
        // Test manual trigger for the first completed server
        const completedServers = allServers.filter((s) => s.syncStatus === "completed");
        if (completedServers.length > 0) {
            console.log(`\n🚀 Manually triggering activity sync for server: ${completedServers[0].name}`);
            await scheduler_1.activityScheduler.triggerServerActivitySync(completedServers[0].id);
            console.log("✅ Manual trigger successful!");
        }
        else {
            console.log("\n⚠️  No completed servers found to test manual sync trigger.");
        }
        // Test starting the scheduler
        console.log("\n⏰ Testing scheduler start...");
        await scheduler_1.activityScheduler.start();
        console.log("✅ Scheduler started successfully!");
        // Wait a bit to see if any periodic jobs trigger
        console.log("\n⏳ Waiting 10 seconds to observe scheduler behavior...");
        await new Promise((resolve) => setTimeout(resolve, 10000));
        console.log("\n🛑 Stopping scheduler...");
        scheduler_1.activityScheduler.stop();
        console.log("\n✅ Test completed successfully!");
    }
    catch (error) {
        console.error("❌ Test failed:", error);
    }
    finally {
        // Cleanup
        console.log("\n🧹 Cleaning up...");
        scheduler_1.activityScheduler.stop();
        await (0, queue_1.closeJobQueue)();
        process.exit(0);
    }
}
// Run the test
testPeriodicSync();
