import { NextRequest, NextResponse } from "next/server";
import { getServer } from "@/lib/db/server";

export const dynamic = "force-dynamic";

export async function POST(request: NextRequest) {
  try {
    const { searchParams } = new URL(request.url);
    const serverId = searchParams.get("serverId");

    if (!serverId) {
      return NextResponse.json(
        { error: "Server ID is required" },
        { status: 400 }
      );
    }

    const serverIdNum = Number(serverId);
    if (isNaN(serverIdNum)) {
      return NextResponse.json({ error: "Invalid server ID" }, { status: 400 });
    }

    // Verify the target server exists
    const targetServer = await getServer({ serverId: serverIdNum });
    if (!targetServer) {
      return NextResponse.json(
        { error: "Target server not found" },
        { status: 404 }
      );
    }

    // Handle import logic here
    return NextResponse.json({
      success: true,
      message: "Import endpoint available",
      server: targetServer.name,
    });
  } catch (error) {
    console.error("Import error:", error);
    return NextResponse.json(
      {
        error: error instanceof Error ? error.message : "Import failed",
        success: false,
      },
      { status: 500 }
    );
  }
}
