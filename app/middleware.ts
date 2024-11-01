import { headers } from "next/headers";
import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { getMe, getServer, getServers, getUser } from "./lib/db";

export async function middleware(request: NextRequest) {
  const pathname = request.nextUrl.pathname;
  const pathParts = pathname.split("/").filter(Boolean);
  const servers = await getServers();
  const me = await getMe();

  // Handle root path "/"
  if (pathname === "/") {
    if (me?.serverId && me.name) {
      const user = await getUser(me.name, me.serverId);
      if (user) {
        return NextResponse.redirect(
          new URL(`/servers/${me.serverId}/dashboard`, request.url)
        );
      }
    }

    if (servers.length > 0) {
      return NextResponse.redirect(
        new URL(`/servers/${servers[0].id}/login`, request.url)
      );
    }

    return NextResponse.redirect(new URL("/setup", request.url));
  }

  // Handle "/servers" path
  if (pathname === "/servers") {
    if (servers.length > 0) {
      return NextResponse.redirect(
        new URL(`/servers/${servers[0].id}/dashboard`, request.url)
      );
    }
    return NextResponse.redirect(new URL("/setup", request.url));
  }

  // Handle "/servers/:id" paths
  if (pathParts[0] === "servers" && pathParts[1]) {
    const serverId = Number(pathParts[1]);
    const server = await getServer(serverId);

    if (!server) {
      return NextResponse.redirect(new URL("/", request.url));
    }

    if (me?.serverId === serverId && me.name) {
      const user = await getUser(me.name, serverId);
      if (user) {
        // User is authenticated for this server, allow access
        return NextResponse.next();
      }
    }

    // User is not authenticated for this server
    if (pathParts[2] !== "login") {
      return NextResponse.redirect(
        new URL(`/servers/${serverId}/login`, request.url)
      );
    }
  }

  // For all other cases, allow the request to proceed
  return NextResponse.next();
}

export const config = {
  matcher: ["/", "/servers", "/servers/:id", "/servers/:id/:path*"],
};
