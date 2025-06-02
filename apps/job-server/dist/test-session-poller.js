"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const database_1 = require("@streamystats/database");
const session_poller_1 = require("./jobs/session-poller");
async function testSessionPoller() {
    console.log("🧪 Testing Session Poller Implementation");
    console.log("======================================");
    try {
        // Check if we have any servers configured
        const serverList = await database_1.db.select().from(database_1.servers);
        if (serverList.length === 0) {
            console.log("⚠️  No servers found in database. Please add a Jellyfin server first.");
            console.log("   You can use the /api/jobs endpoints to sync servers.");
            return;
        }
        console.log(`📋 Found ${serverList.length} server(s) in database:`);
        serverList.forEach((server, index) => {
            console.log(`   ${index + 1}. ${server.name} (${server.url})`);
        });
        console.log("\n🚀 Starting session poller...");
        await session_poller_1.sessionPoller.start();
        console.log("📊 Session poller status:", session_poller_1.sessionPoller.getStatus());
        // Test getting active sessions for each server
        console.log("\n🔍 Testing active sessions retrieval:");
        for (const server of serverList) {
            const activeSessions = session_poller_1.sessionPoller.getActiveSessions(server.id);
            if (activeSessions.length > 0) {
                activeSessions.forEach((session, index) => {
                    console.log(`     ${index + 1}. ${session.userName} watching "${session.itemName}" (${session.playDuration}s)`);
                });
            }
        }
        console.log("\n⏱️  Letting poller run for 30 seconds to test session tracking...");
        console.log("    (Check your Jellyfin server and start playing some content to see it tracked)");
        // Let it run for 30 seconds to demonstrate
        setTimeout(() => {
            console.log("\n📈 Final session status after 30 seconds:");
            console.log("📊 Session poller status:", session_poller_1.sessionPoller.getStatus());
            for (const server of serverList) {
                const activeSessions = session_poller_1.sessionPoller.getActiveSessions(server.id);
                if (activeSessions.length > 0) {
                    console.log(`   Server ${server.name}: ${activeSessions.length} active sessions`);
                    activeSessions.forEach((session, index) => {
                        console.log(`     ${index + 1}. ${session.userName} watching "${session.itemName}" (${session.playDuration}s, paused: ${session.isPaused})`);
                    });
                }
            }
            console.log("\n🛑 Stopping session poller...");
            session_poller_1.sessionPoller.stop();
            console.log("✅ Session poller test completed!");
            process.exit(0);
        }, 30000);
    }
    catch (error) {
        console.error("❌ Error testing session poller:", error);
        session_poller_1.sessionPoller.stop();
        process.exit(1);
    }
}
// Handle graceful shutdown
process.on("SIGINT", () => {
    console.log("\n🛑 Interrupted - stopping session poller...");
    session_poller_1.sessionPoller.stop();
    process.exit(0);
});
// Run the test
testSessionPoller().catch(console.error);
