import { getToken } from "@/lib/token";
import { NextRequest, NextResponse } from "next/server";

export async function POST(
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

  let formData: FormData;
  try {
    formData = await req.formData();
  } catch {
    return NextResponse.json({ error: "Invalid form data" }, { status: 400 });
  }

  const file = formData.get("file");
  if (!(file instanceof File)) {
    return NextResponse.json({ error: "No file provided" }, { status: 400 });
  }

  // Build multipart form for upstream
  const upstreamForm = new FormData();
  // Convert File → Blob for Node fetch
  const buffer = await file.arrayBuffer();
  upstreamForm.set("file", new Blob([buffer]), file.name);

  const upstreamRes = await fetch(
    `${process.env.API_URL}/servers/${serverId}/backup/import`,
    {
      method: "POST",
      headers: { Authorization: `Bearer ${token}` },
      body: upstreamForm,
    }
  );

  const payload = await upstreamRes
    .json()
    .catch(() => ({ error: "Unable to parse response" }));

  if (!upstreamRes.ok) {
    return NextResponse.json(
      { error: payload.error || "Import failed" },
      { status: upstreamRes.status }
    );
  }

  return NextResponse.json(payload, { status: upstreamRes.status });
}
