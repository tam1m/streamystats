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
const connection_1 = require("./src/db/connection");
const schema_1 = require("./src/db/schema");
const queue_1 = require("./src/jobs/queue");
const workers_1 = require("./src/jellyfin/workers");
// Load environment variables
dotenv.config();
async function testRecentItemsSync() {
    try {
        console.log("🧪 Testing Recently Added Items Sync");
        console.log("====================================");
        // Get all servers
        console.log("🔍 Fetching servers...");
        const allServers = await connection_1.db.select().from(schema_1.servers);
        console.log(`Found ${allServers.length} servers:`);
        allServers.forEach((server, index) => {
            console.log(`  ${index + 1}. ${server.name} (ID: ${server.id}) - Status: ${server.syncStatus}`);
        });
        if (allServers.length === 0) {
            console.log("❌ No servers found. Please add a server first.");
            return;
        }
        // Get job queue
        const boss = await (0, queue_1.getJobQueue)();
        // Test manual trigger for the first completed server
        const completedServers = allServers.filter((s) => s.syncStatus === "completed");
        if (completedServers.length > 0) {
            const server = completedServers[0];
            console.log(`\n🚀 Triggering recently added items sync for server: ${server.name}`);
            // Queue the job
            await boss.send(workers_1.JELLYFIN_JOB_NAMES.RECENT_ITEMS_SYNC, {
                serverId: server.id,
                options: {
                    itemOptions: {
                        recentItemsLimit: 50, // Test with smaller limit
                    },
                },
            });
            console.log("✅ Recently added items sync job queued successfully!");
            console.log("📋 Job details:");
            console.log(`   - Server: ${server.name} (ID: ${server.id})`);
            console.log(`   - Limit: 50 items per library`);
            console.log(`   - Job type: ${workers_1.JELLYFIN_JOB_NAMES.RECENT_ITEMS_SYNC}`);
            console.log("\n⏳ Waiting 15 seconds to see job processing...");
            await new Promise((resolve) => setTimeout(resolve, 15000));
        }
        else {
            console.log("\n⚠️  No completed servers found. Available servers:");
            allServers.forEach((server) => {
                console.log(`   - ${server.name}: ${server.syncStatus}`);
            });
            if (allServers.length > 0) {
                const server = allServers[0];
                console.log(`\n🔄 Trying with first available server: ${server.name}`);
                await boss.send(workers_1.JELLYFIN_JOB_NAMES.RECENT_ITEMS_SYNC, {
                    serverId: server.id,
                    options: {
                        itemOptions: {
                            recentItemsLimit: 50,
                        },
                    },
                });
                console.log("✅ Job queued for available server!");
                console.log("\n⏳ Waiting 15 seconds to see job processing...");
                await new Promise((resolve) => setTimeout(resolve, 15000));
            }
        }
        console.log("\n✅ Test completed! Check the main application logs for sync activity.");
    }
    catch (error) {
        console.error("❌ Test failed:", error);
    }
    finally {
        // Cleanup
        console.log("\n🧹 Cleaning up...");
        await (0, queue_1.stopJobQueue)();
        process.exit(0);
    }
}
// Run the test
testRecentItemsSync();
