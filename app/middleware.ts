"use server";

import type { NextRequest } from "next/server";
import { NextResponse, URLPattern } from "next/server";
import { getServers, User } from "./lib/db";
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

const PATTERNS = [
  [
    new URLPattern({ pathname: "/servers/:id/users/:name" }),
    ({ pathname }: { pathname: { groups: { id: string } } }) => pathname.groups,
  ],
  [
    new URLPattern({ pathname: "/servers/:id/:page" }),
    ({ pathname }: { pathname: { groups: { id: string } } }) => pathname.groups,
  ],
  [
    new URLPattern({ pathname: "/*" }),
    ({ pathname }: { pathname: { groups: {} } }) => pathname.groups,
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
  return result;
};

const getMe = async (request: NextRequest): Promise<Result<UserMe>> => {
  const c = request.cookies;
  const userStr = c.get("streamystats-user");

  try {
    const me = userStr?.value ? JSON.parse(userStr.value) : undefined;
    if (me && me.name && me.serverId) {
      const isValid = await validateUserAuth(request, me);

      if (isValid) {
        return {
          type: ResultType.Success,
          data: me,
        };
      } else {
        return {
          type: ResultType.Error,
          error: "Invalid user cookie",
        };
      }
    }
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

/**
 * @param me The user object from the cookie
 * Validates that the user stored in the cokkie is valid and has access to the server.
 */
const validateUserAuth = async (request: NextRequest, me: UserMe) => {
  const c = request.cookies;
  try {
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

    if (user) return true;
  } catch (e) {
    console.error("Failed to validate user auth", e);
  }

  return false;
};

export async function middleware(request: NextRequest) {
  const response = NextResponse.next();

  const { id, page } = params(request.url);

  const servers = await getServers();

  if (!id && !page) {
    return response;
  }

  // If there are no servers, redirect to /setup
  if (servers.length === 0) {
    console.log("No servers found, redirecting to /setup");
    return NextResponse.redirect(new URL("/setup", request.url));
  }

  if (page && id === "undefined") {
    return NextResponse.redirect(new URL(`/not-found`, request.url));
  }

  // If the server does not exist
  if (!servers.some((s) => Number(s.id) === Number(id))) {
    console.log(
      `Server ${id} not found, redirecting to /servers/` + servers[0].id
    );
    return NextResponse.redirect(
      new URL(`/servers/${servers[0].id}/login`, request.url)
    );
  }

  // Validate auth for secure pages
  if (page && id && page !== "login") {
    // Get user from cookies if exists
    const meResult = await getMe(request);

    // If the user is not logged in
    if (meResult.type === ResultType.Error) {
      console.error("User is not logged in, removing cookies");
      response.cookies.delete("streamystats-user");
      response.cookies.delete("streamystats-token");

      return NextResponse.redirect(
        new URL(`/servers/${servers[0].id}/login`, request.url)
      );
    }

    // If the user is trying to access a server they are not a member of
    if (meResult.type === ResultType.Success) {
      if (Number(meResult.data.serverId) !== Number(id)) {
        console.log(
          "User is trying to access a server they are not a member of"
        );
        return NextResponse.redirect(
          new URL(`/servers/${id}/login`, request.url)
        );
      }
    }
  }

  // For all other cases, allow the request to proceed
  return response;
}
