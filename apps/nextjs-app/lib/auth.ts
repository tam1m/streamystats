"use server";

import { cookies, headers } from "next/headers";
import { getServer } from "./db/server";

export const login = async ({
  serverId,
  username,
  password,
}: {
  serverId: number;
  username: string;
  password?: string | null;
}): Promise<void> => {
  // Make login request to jellyfin server directly
  const server = await getServer(serverId);

  if (!server) {
    throw new Error("Server not found");
  }

  const res = await fetch(`${server.url}/Users/AuthenticateByName`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-Emby-Token": server.apiKey,
    },
    body: JSON.stringify({ Username: username, Pw: password }),
  });

  if (!res.ok) {
    throw new Error("Failed to login");
  }

  const data = await res.json();

  console.log(data);

  const accessToken = data["AccessToken"];
  const user = data["User"];

  const h = await headers();

  const secure = h.get("x-forwarded-proto") === "https";

  const maxAge = 30 * 24 * 60 * 60;

  const isAdmin = data["User"]["Policy"]["IsAdministrator"];

  const c = await cookies();

  c.set("streamystats-token", accessToken, {
    httpOnly: true,
    sameSite: "lax",
    path: "/",
    maxAge,
    secure,
  });

  c.set(
    "streamystats-user",
    JSON.stringify({
      name: user.Name,
      id: user.Id,
      serverId,
    }),
    {
      httpOnly: true,
      sameSite: "lax",
      path: "/",
      maxAge,
      secure,
    }
  );

  c.set("show-admin-statistics", isAdmin ? "true" : "false", {
    httpOnly: true,
    sameSite: "lax",
    path: "/",
    maxAge,
    secure,
  });
};
