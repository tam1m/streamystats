import { getItemStatistics } from "@/lib/db";

export const GET = async (req: Request) => {
  const { searchParams } = new URL(req.url);
  const serverId = searchParams.get("serverId");
  const itemId = searchParams.get("itemId");
  if (!serverId || !itemId) {
    return new Response("Missing serverId or itemId", { status: 400 });
  }
  const data = await getItemStatistics(serverId, itemId);
  return Response.json(data);
};
