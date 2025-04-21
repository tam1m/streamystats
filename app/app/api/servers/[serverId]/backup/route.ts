import { getToken } from "@/lib/token";
import { NextRequest, NextResponse } from "next/server";

export async function GET(
  req: NextRequest,
  { params }: { params: { serverId: string } }
) {
  const { serverId } = params;
  const token = await getToken();
  if (!token) {
    return NextResponse.json(
      { error: "Not authenticated. Please log in again." },
      { status: 401 }
    );
  }

  const upstream = await fetch(
    `${process.env.API_URL}/servers/${serverId}/backup/export`,
    {
      headers: { Authorization: `Bearer ${token}` },
    }
  );

  if (!upstream.ok) {
    const err = await upstream.json().catch(() => ({ error: "Export failed" }));
    return NextResponse.json(
      { error: err.error || "Failed to export database" },
      { status: upstream.status }
    );
  }

  // mirror only content-type & content-disposition
  const headers = new Headers();
  for (const [key, value] of upstream.headers) {
    if (/^content-(type|disposition)$/i.test(key)) {
      headers.set(key, value);
    }
  }

  return new NextResponse(upstream.body, {
    status: upstream.status,
    headers,
  });
}
