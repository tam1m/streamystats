"use server";

import { cookies } from "next/headers";

const PREFERRED_SERVER_COOKIE = "streamystats-preferred-server";
const COOKIE_MAX_AGE = 365 * 24 * 60 * 60; // 1 year

export const setPreferredServer = async (serverId: number): Promise<void> => {
  const c = cookies();
  c.set(PREFERRED_SERVER_COOKIE, serverId.toString(), {
    httpOnly: true,
    sameSite: "lax",
    path: "/",
    maxAge: COOKIE_MAX_AGE,
    secure: process.env.NODE_ENV === "production",
  });
};

export const getPreferredServer = async (): Promise<number | null> => {
  const c = cookies();
  const preferredServerCookie = c.get(PREFERRED_SERVER_COOKIE);

  if (preferredServerCookie?.value) {
    const serverId = parseInt(preferredServerCookie.value, 10);
    return isNaN(serverId) ? null : serverId;
  }

  return null;
};

export const clearPreferredServer = async (): Promise<void> => {
  const c = cookies();
  c.delete(PREFERRED_SERVER_COOKIE);
};
