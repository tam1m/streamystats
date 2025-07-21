import { getItemDetails } from "@/lib/db/items";
import { NextRequest } from "next/server";

export const dynamic = "force-dynamic";

export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ itemId: string }> }
) {
  const { itemId } = await params;

  try {
    if (!itemId) {
      return new Response(
        JSON.stringify({
          error: "itemId is required",
        }),
        {
          status: 400,
          headers: {
            "Content-Type": "application/json",
          },
        }
      );
    }

    const itemDetails = await getItemDetails({
      itemId,
    });

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
