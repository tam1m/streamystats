import { NextRequest } from "next/server";
import { getServer } from "@/lib/db/server";
import {
  db,
  sessions,
  activities,
  users,
  items,
  libraries,
} from "@streamystats/database";
import { eq } from "drizzle-orm";

export const dynamic = "force-dynamic";

export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ serverId: string }> }
) {
  try {
    const { serverId } = await params;

    // Verify server exists and user has access
    const server = await getServer({ serverId });
    if (!server) {
      return new Response(JSON.stringify({ error: "Server not found" }), {
        status: 404,
        headers: { "Content-Type": "application/json" },
      });
    }

    // Export all session and related data for this server
    console.log(`Starting export for server ${server.id} (${server.name})`);

    const exportData = {
      exportInfo: {
        timestamp: new Date().toISOString(),
        serverName: server.name,
        serverId: server.id,
        version: "streamystats-v2",
        exportType: "full",
      },

      // Core session data - all sessions for this server
      sessions: await db.query.sessions.findMany({
        where: eq(sessions.serverId, server.id),
        with: {
          user: true,
          item: true,
          server: true,
        },
      }),

      // User activities for this server
      activities: await db.query.activities.findMany({
        where: eq(activities.serverId, server.id),
        with: {
          user: true,
          server: true,
        },
      }),

      // Users for this server
      users: await db.query.users.findMany({
        where: eq(users.serverId, server.id),
        with: {
          server: true,
        },
      }),

      // Media items for this server
      items: await db.query.items.findMany({
        where: eq(items.serverId, server.id),
        with: {
          library: true,
          server: true,
        },
      }),

      // Libraries for this server
      libraries: await db.query.libraries.findMany({
        where: eq(libraries.serverId, server.id),
        with: {
          server: true,
        },
      }),

      // Server info
      server: {
        id: server.id,
        name: server.name,
        url: server.url,
        // Don't export sensitive data like API keys
        createdAt: server.createdAt,
        updatedAt: server.updatedAt,
        lastSyncCompleted: server.lastSyncCompleted,
        syncStatus: server.syncStatus,
      },
    };

    const sessionCount = exportData.sessions.length;
    const activityCount = exportData.activities.length;
    const userCount = exportData.users.length;
    const itemCount = exportData.items.length;

    console.log(
      `Export completed for server ${server.name}: ${sessionCount} sessions, ${activityCount} activities, ${userCount} users, ${itemCount} items`
    );

    // Generate filename with timestamp
    const timestamp = new Date().toISOString().split("T")[0];
    const filename = `streamystats-backup-${server.name.replace(
      /[^a-zA-Z0-9]/g,
      "-"
    )}-${timestamp}.json`;

    // Return JSON response with proper headers for download
    return new Response(JSON.stringify(exportData, null, 2), {
      status: 200,
      headers: {
        "Content-Type": "application/json",
        "Content-Disposition": `attachment; filename="${filename}"`,
        "X-Export-Count": sessionCount.toString(),
        "X-Export-Server": server.name,
      },
    });
  } catch (error) {
    console.error("Export error:", error);
    return new Response(
      JSON.stringify({
        error: "Export failed",
        message: error instanceof Error ? error.message : "Unknown error",
      }),
      {
        status: 500,
        headers: { "Content-Type": "application/json" },
      }
    );
  }
}
