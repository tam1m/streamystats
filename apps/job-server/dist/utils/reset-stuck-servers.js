"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.resetStuckServers = resetStuckServers;
exports.forceResetServer = forceResetServer;
const database_1 = require("@streamystats/database");
const drizzle_orm_1 = require("drizzle-orm");
/**
 * Utility to reset servers that are stuck in "syncing" status
 * This can happen if a job hangs or fails to complete properly
 */
async function resetStuckServers() {
    try {
        console.log("🔍 Checking for stuck servers...");
        // Find servers that have been "syncing" for more than 1 hour
        const oneHourAgo = new Date(Date.now() - 60 * 60 * 1000);
        const stuckServers = await database_1.db
            .select()
            .from(database_1.servers)
            .where((0, drizzle_orm_1.eq)(database_1.servers.syncStatus, "syncing"));
        if (stuckServers.length === 0) {
            console.log("✅ No stuck servers found");
            return;
        }
        console.log(`🚨 Found ${stuckServers.length} potentially stuck servers:`);
        for (const server of stuckServers) {
            const lastSyncStarted = server.lastSyncStarted
                ? new Date(server.lastSyncStarted)
                : null;
            const duration = lastSyncStarted
                ? Math.round((Date.now() - lastSyncStarted.getTime()) / (1000 * 60))
                : "unknown";
            console.log(`   - ${server.name} (ID: ${server.id})`);
            console.log(`     Status: ${server.syncStatus}`);
            console.log(`     Progress: ${server.syncProgress}`);
            console.log(`     Duration: ${duration} minutes`);
            console.log(`     Last sync started: ${server.lastSyncStarted}`);
            console.log(`     Last sync completed: ${server.lastSyncCompleted}`);
            // Reset servers that have been syncing for more than 1 hour
            if (lastSyncStarted && lastSyncStarted < oneHourAgo) {
                console.log(`   🔄 Resetting server ${server.name}...`);
                await database_1.db
                    .update(database_1.servers)
                    .set({
                    syncStatus: "completed",
                    syncProgress: "completed",
                    syncError: "Reset due to stuck sync (>1 hour)",
                    updatedAt: new Date(),
                })
                    .where((0, drizzle_orm_1.eq)(database_1.servers.id, server.id));
                console.log(`   ✅ Reset completed for ${server.name}`);
            }
            else {
                console.log(`   ⏳ Server ${server.name} hasn't been stuck long enough to reset (< 1 hour)`);
            }
        }
        console.log("🏁 Stuck server check completed");
    }
    catch (error) {
        console.error("❌ Error checking/resetting stuck servers:", error);
        throw error;
    }
}
/**
 * Force reset a specific server by ID
 */
async function forceResetServer(serverId) {
    try {
        console.log(`🔄 Force resetting server ID: ${serverId}...`);
        const result = await database_1.db
            .update(database_1.servers)
            .set({
            syncStatus: "completed",
            syncProgress: "completed",
            syncError: "Force reset via utility",
            updatedAt: new Date(),
        })
            .where((0, drizzle_orm_1.eq)(database_1.servers.id, serverId))
            .returning();
        if (result.length === 0) {
            console.log(`❌ Server ID ${serverId} not found`);
            return;
        }
        console.log(`✅ Force reset completed for server: ${result[0].name}`);
    }
    catch (error) {
        console.error(`❌ Error force resetting server ${serverId}:`, error);
        throw error;
    }
}
// CLI usage if run directly
if (require.main === module) {
    const [, , action, serverId] = process.argv;
    if (action === "reset" && serverId) {
        forceResetServer(parseInt(serverId))
            .then(() => process.exit(0))
            .catch(() => process.exit(1));
    }
    else {
        resetStuckServers()
            .then(() => process.exit(0))
            .catch(() => process.exit(1));
    }
}
