"use server";

import { cookies } from "next/headers";

export type UserMe = {
  id?: string;
  name?: string;
  serverId?: number;
};

export const getMe = async (): Promise<UserMe | null> => {
  const c = cookies();
  const userStr = c.get("streamystats-user");
  const user = userStr?.value ? JSON.parse(userStr.value) : undefined;

  return user ? (user as UserMe) : null;
};
