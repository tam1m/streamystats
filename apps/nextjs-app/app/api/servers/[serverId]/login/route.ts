// app/api/auth/login/route.ts
import { login } from "@/lib/auth";
import { NextRequest } from "next/server";

export async function POST(
  request: NextRequest,
  { params }: { params: { serverId: string } }
) {
  try {
    const body = await request.json();
    const { username, password } = body;
    const { serverId } = params;

    if (!serverId || !username) {
      return Response.json(
        { error: "serverId and username are required" },
        { status: 400 }
      );
    }

    // Use your existing login function that sets cookies
    await login({
      serverId: Number(serverId),
      username,
      password,
    });

    return Response.json({ success: true });
  } catch (error) {
    console.error("Login error:", error);
    return Response.json({ error: "Login failed" }, { status: 401 });
  }
}
