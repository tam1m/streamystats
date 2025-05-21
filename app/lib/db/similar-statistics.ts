"use server";

import { Item } from "../db";
import { getToken } from "../token";

export const getSimilarStatistics = async (
  serverId: number | string
): Promise<Item[]> => {
  try {
    const res = await fetch(
      `${process.env.API_URL}/servers/${serverId}/statistics/recommendations/me`,
      {
        cache: "no-store",
        headers: {
          Authorization: `Bearer ${await getToken()}`,
          "Content-Type": "application/json",
        },
        next: {
          revalidate: 60 * 60,
        },
      }
    );

    if (!res.ok) {
      console.error(
        `Error fetching similar statistics: ${res.status} ${res.statusText}`
      );
      return [];
    }

    const data = await res.json();
    return data.data || [];
  } catch (error) {
    console.error("Error fetching similar statistics:", error);
    return [];
  }
};
