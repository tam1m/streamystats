"use server";

import { Item } from "../db";
import { getToken } from "../token";

export interface RecommendationItem {
  item: Item;
  similarity: number;
  based_on: Item[];
}

export const getSimilarStatistics = async (
  serverId: number | string
): Promise<RecommendationItem[]> => {
  try {
    const res = await fetch(
      `${process.env.API_URL}/servers/${serverId}/statistics/recommendations/me?limit=20`,
      {
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
    console.log(data);
    return data.data || [];
  } catch (error) {
    console.error("Error fetching similar statistics:", error);
    return [];
  }
};

export const hideRecommendation = async (
  serverId: number | string,
  itemId: string
): Promise<{ success: boolean; message?: string; error?: string }> => {
  try {
    const res = await fetch(
      `${process.env.API_URL}/servers/${serverId}/statistics/recommendations/hide/${itemId}`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${await getToken()}`,
          "Content-Type": "application/json",
        },
      }
    );

    const data = await res.json();

    if (!res.ok) {
      return {
        success: false,
        error:
          data.error ||
          `Failed to hide recommendation: ${res.status} ${res.statusText}`,
      };
    }

    return data;
  } catch (error) {
    console.error("Error hiding recommendation:", error);
    return {
      success: false,
      error: "Network error while hiding recommendation",
    };
  }
};
