"use server";

import { setPreferredServer as setPreferredServerCookie } from "@/lib/preferred-server";

export const setPreferredServerAction = async (
  serverId: number
): Promise<void> => {
  await setPreferredServerCookie(serverId);
};
