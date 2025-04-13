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
    // Check for Authorization header from client request first
    let token = req.headers.get("Authorization");

    // If no Authorization header is present, fallback to getToken()
    if (!token) {
      token = (await getToken()) ?? null;
    }

    const res = await fetch(
      `${process.env.API_URL}/servers/${serverId}/statistics/items/${itemId}`,
      {
        cache: "no-store",
        headers: {
          Authorization: `Bearer ${token}`,
          "Content-Type": "application/json",
        },
      }
    );

    if (!res.ok) {
      const errorText = await res.text();
      // Pass through the error status from the API
      if (res.status === 404)
        return Response.json({ error: "Item not found" }, { status: 404 });
      if (res.status === 401)
        return Response.json({ error: "Unauthorized" }, { status: 401 });

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
