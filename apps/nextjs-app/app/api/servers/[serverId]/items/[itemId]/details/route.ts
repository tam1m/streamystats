import { getItemDetails } from "@/lib/db/items";
import { showAdminStatistics } from "@/utils/adminTools";
import { NextRequest } from "next/server";

export const dynamic = "force-dynamic";

export async function GET(
  request: NextRequest,
  { params }: { params: { serverId: string; itemId: string } }
) {
  try {
    const { serverId, itemId } = params;

    if (!serverId || !itemId) {
      return new Response(
        JSON.stringify({
          error: "serverId and itemId are required parameters",
        }),
        {
          status: 400,
          headers: {
            "Content-Type": "application/json",
          },
        }
      );
    }

    // Check if user should see admin statistics (combines admin status + preference)
    const isAdmin = await showAdminStatistics();

    // Get item details with statistics
    const itemDetails = await getItemDetails(Number(serverId), itemId, isAdmin);

    if (!itemDetails) {
      return new Response(
        JSON.stringify({
          error: "Item not found",
        }),
        {
          status: 404,
          headers: {
            "Content-Type": "application/json",
          },
        }
      );
    }

    return new Response(JSON.stringify(itemDetails), {
      status: 200,
      headers: {
        "Content-Type": "application/json",
      },
    });
  } catch (error) {
    console.error("Error fetching item details:", error);
    return new Response(
      JSON.stringify({
        error: "Failed to fetch item details",
        message: error instanceof Error ? error.message : "Unknown error",
      }),
      {
        status: 500,
        headers: {
          "Content-Type": "application/json",
        },
      }
    );
  }
}
