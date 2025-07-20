import { getItemDetails } from "@/lib/db/items";
import { requireApiKey } from "@/lib/api-auth";
import { NextRequest } from "next/server";

export const dynamic = "force-dynamic";

export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ serverId: string; itemId: string }> }
) {
  try {
    const { serverId, itemId } = await params;

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

    // Check API key authentication against the specific server
    const authError = await requireApiKey(request, Number(serverId));
    if (authError) {
      return authError;
    }

    // Get item details with admin privileges (full statistics)
    const itemDetails = await getItemDetails(Number(serverId), itemId, true);

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
