import { getToken } from "@/lib/token";
import { NextRequest } from "next/server";

export const GET = async (
  req: NextRequest,
  { params }: { params: { serverId: string; itemId: string } }
) => {
  const { serverId, itemId } = params;

  if (!serverId || !itemId) {
    return Response.json(
      { error: "Missing serverId or itemId" },
      { status: 400 }
    );
  }

  try {
    const res = await fetch(
      `${process.env.API_URL}/servers/${serverId}/statistics/items/${itemId}`,
      {
        cache: "no-store",
        headers: {
          Authorization: `Bearer ${await getToken()}`,
          "Content-Type": "application/json",
        },
      }
    );

    if (!res.ok) {
      const errorText = await res.text();
      // Pass through the error status from the API
      return Response.json(
        { error: `API error: ${errorText}` },
        { status: res.status }
      );
    }

    const data = await res.json();

    if (!data || !data.data) {
      return Response.json({ error: "Item not found" }, { status: 404 });
    }

    return Response.json(data.data);
  } catch (error) {
    console.error("Error fetching item data:", error);
    return Response.json({ error: "Internal server error" }, { status: 500 });
  }
};
