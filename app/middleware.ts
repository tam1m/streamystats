"use server";

import type { NextRequest } from "next/server";
import { NextResponse, URLPattern } from "next/server";
import { getServer, getServers, User } from "./lib/db";

const PATTERNS = [
  [
    new URLPattern({ pathname: "/" }),
    ({ pathname }: { pathname: { groups: {} } }) => pathname.groups,
  ],
  [
    new URLPattern({ pathname: "/servers/:id" }),
    ({ pathname }: { pathname: { groups: { id: string } } }) => pathname.groups,
  ],
  [
    new URLPattern({ pathname: "/servers/:id/:page" }),
    ({ pathname }: { pathname: { groups: { id: string } } }) => pathname.groups,
  ],
];

const params = (url: string) => {
  const input = url.split("?")[0];
  let result: any = {};

  for (const [pattern, handler] of PATTERNS) {
    // @ts-ignore
    const patternResult = pattern.exec(input);
    if (patternResult !== null && "pathname" in patternResult) {
      // @ts-ignore
      result = handler(patternResult);
      break;
    }
  }
  console.log(result);
  return result;
};

export async function middleware(request: NextRequest) {
  const { id } = params(request.url);
  const pathname = request.nextUrl.pathname;
  const pathParts = pathname.split("/").filter(Boolean);
  const servers = await getServers();
  const c = request.cookies;
  const userStr = c.get("streamystats-user");
  const me = userStr?.value ? JSON.parse(userStr.value) : undefined;

  // Handle root path "/"
  if (pathname === "/") {
    if (me && me.serverId && me.name) {
      const user: User = await fetch(
        process.env.API_URL + "/servers/" + me.serverId + "/users/" + me.name,
        {
          cache: "no-store",
          headers: {
            Authorization: `Bearer ${c.get("streamystats-token")?.value}`,
            "Content-Type": "application/json",
          },
        }
      )
        .then((res) => res.json())
        .then((res) => res.data);
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
      const user: User = await fetch(
        process.env.API_URL + "/servers/" + me.serverId + "/users/" + me.name,
        {
          cache: "no-store",
          headers: {
            Authorization: `Bearer ${c.get("streamystats-token")?.value}`,
            "Content-Type": "application/json",
          },
        }
      )
        .then((res) => res.json())
        .then((res) => res.data);
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
