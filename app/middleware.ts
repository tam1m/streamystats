"use server";

import type { NextRequest } from "next/server";
import { NextResponse, URLPattern } from "next/server";
import { User, getServers } from "./lib/db";
import { UserMe } from "./lib/me";

enum ResultType {
  Success = "SUCCESS",
  Error = "ERROR",
}

type Result<T> =
  | {
      type: ResultType.Success;
      data: T;
    }
  | {
      type: ResultType.Error;
      error: string;
    };

export const config = {
  matcher: [
    "/((?!api|_next/static|_next/image|favicon.ico|icon.png|not-found).*)",
  ],
};

const PATTERNS = [
  [
    new URLPattern({ pathname: "/servers/:id/users/:name" }),
    ({ pathname }: { pathname: { groups: { id: string; name: string } } }) =>
      pathname.groups,
  ],
  [
    new URLPattern({ pathname: "/servers/:id/items/:itemId" }),
    ({ pathname }: { pathname: { groups: { id: string; itemId: string } } }) =>
      pathname.groups,
  ],
  [
    new URLPattern({ pathname: "/servers/:id/:page" }),
    ({ pathname }: { pathname: { groups: { id: string } } }) => pathname.groups,
  ],
  [
    new URLPattern({ pathname: "/not-found" }),
    ({ pathname }: { pathname: { groups: Record<string, string> } }) =>
      pathname.groups,
  ],
  [
    new URLPattern({ pathname: "/*" }),
    ({ pathname }: { pathname: { groups: Record<string, string> } }) =>
      pathname.groups,
  ],
];

const ADMIN_ONLY_PATHS = ["history", "settings", "activities"];
const PUBLIC_PATHS = ["login", "setup"];

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
  return result;
};

const getMe = async (request: NextRequest): Promise<Result<UserMe>> => {
  const c = request.cookies;
  const userStr = c.get("streamystats-user");

  try {
    const me = userStr?.value ? JSON.parse(userStr.value) : undefined;
    if (me?.name && me.serverId) {
      const isValid = await validateUserAuth(request, me);
      if (isValid) {
        return {
          type: ResultType.Success,
          data: me,
        };
      }
      return {
        type: ResultType.Error,
        error: "Invalid user cookie",
      };
    }

    console.warn("Missing required fields in cookie");
  } catch (e) {
    console.error(
      "Failed to parse user cookie. The cookie probably has incorrect information.",
      e
    );
  }

  return {
    type: ResultType.Error,
    error: "Invalid user cookie",
  };
};

const isUserAdmin = async (
  request: NextRequest,
  me: UserMe
): Promise<boolean> => {
  const c = request.cookies;
  try {
    const user: User = await fetch(
      `${process.env.API_URL}/servers/${me.serverId}/users/${me.id}`,
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

    // Return true if user has admin role/privileges
    return user && user.is_administrator === true;
  } catch (e) {
    console.error("Failed to check if user is admin", e);
    return false;
  }
};

/**
 * @param me The user object from the cookie
 * Validates that the user stored in the cokkie is valid and has access to the server.
 */
const validateUserAuth = async (request: NextRequest, me: UserMe) => {
  const c = request.cookies;
  try {
    const user: User = await fetch(
      `${process.env.API_URL}/servers/${me.serverId}/users/${me.id}`,
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

    if (user) return true;
  } catch (e) {
    console.error("Failed to validate user auth", e);
  }

  console.warn("User not found in server", me.serverId, "for user", me.name);
  return false;
};

export async function middleware(request: NextRequest) {
  const response = NextResponse.next();

  const { id, page, name } = params(request.url);

  const servers = await getServers();

  const isSetup = request.url.includes("/setup");

  console.log(request.url, isSetup);

  // If there are no servers, redirect to /setup
  if (servers.length === 0) {
    if (isSetup) return response;
    return NextResponse.redirect(new URL("/setup", request.url));
  }

  // If the server does not exist
  if (id && !servers.some((s) => Number(s.id) === Number(id))) {
    return NextResponse.redirect(new URL("/not-found", request.url));
  }

  // If the page is public, return the response
  if (PUBLIC_PATHS.includes(page)) return response;

  // Get user from cookies if exists
  const meResult = await getMe(request);

  // If the user is not logged in
  if (meResult.type === ResultType.Error) {
    console.error("User is not logged in, removing cookies.", meResult.error);
    response.cookies.delete("streamystats-user");
    response.cookies.delete("streamystats-token");
    return NextResponse.redirect(new URL(`/servers/${id}/login`, request.url));
  }

  // If the user is trying to access a server they are not a member of
  if (meResult.type === ResultType.Success && id) {
    if (Number(meResult.data.serverId) !== Number(id)) {
      console.warn(
        "User is trying to access a server they are not a member of"
      );
      return NextResponse.redirect(
        new URL(`/servers/${id}/login`, request.url)
      );
    }

    const isAdmin = await isUserAdmin(request, meResult.data);

    // Check if user is trying to access another users page (/servers/{x}/users/[name])
    if (name) {
      if (name && name !== meResult.data.name && !isAdmin) {
        return NextResponse.redirect(new URL("/not-found", request.url));
      }
    }

    // Check admin permission for restricted paths
    if (ADMIN_ONLY_PATHS.includes(page)) {
      if (!isAdmin) {
        return NextResponse.redirect(new URL("/not-found", request.url));
      }
    }
  }

  // For all other cases, allow the request to proceed
  return response;
}
