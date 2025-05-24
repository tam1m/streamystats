"use server";

import { Item } from "../db";
import { getToken } from "../token";

export const getSimilarStatistics = async (
  serverId: number | string
): Promise<Item[]> => {
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

export const getContextualRecommendations = async (
  serverId: number | string,
  context: "auto" | "weekend" | "weekday" | "evening" | "quick_watch" = "auto",
  limit: number = 20
): Promise<Item[]> => {
  try {
    const res = await fetch(
      `${process.env.API_URL}/servers/${serverId}/statistics/recommendations/contextual?limit=${limit}&context=${context}`,
      {
        headers: {
          Authorization: `Bearer ${await getToken()}`,
          "Content-Type": "application/json",
        },
        next: {
          revalidate: 60 * 30, // Cache for 30 minutes (contextual changes more frequently)
        },
      }
    );

    if (!res.ok) {
      console.error(
        `Error fetching contextual recommendations: ${res.status} ${res.statusText}`
      );
      return [];
    }

    const data = await res.json();
    return data.data || [];
  } catch (error) {
    console.error("Error fetching contextual recommendations:", error);
    return [];
  }
};

export const getGenreBoostedRecommendations = async (
  serverId: number | string,
  genre?: string
): Promise<Item[]> => {
  try {
    const url = new URL(
      `${process.env.API_URL}/servers/${serverId}/statistics/recommendations/genre-boosted`
    );
    if (genre) {
      url.searchParams.append("genre", genre);
    }

    const res = await fetch(url.toString(), {
      headers: {
        Authorization: `Bearer ${await getToken()}`,
        "Content-Type": "application/json",
      },
      next: {
        revalidate: 60 * 30, // 30 minutes
      },
    });

    if (!res.ok) {
      console.error(
        `Error fetching genre-boosted recommendations: ${res.status} ${res.statusText}`
      );
      return [];
    }

    const data = await res.json();
    return data.data || [];
  } catch (error) {
    console.error("Error fetching genre-boosted recommendations:", error);
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
