"use server";

import { getToken } from "../token";

export const saveOpenAIKey = async (
  serverId: string | number,
  apiKey: string
) => {
  try {
    const response = await fetch(
      `${process.env.API_URL}/admin/servers/${serverId}/settings`,
      {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${await getToken()}`,
        },
        body: JSON.stringify({ open_ai_api_token: apiKey }),
      }
    );
    if (!response.ok) {
      throw new Error("Failed to save OpenAI API key");
    }
  } catch (error) {
    console.error("Error saving OpenAI API key:", error);
    throw error;
  }
};

export interface EmbeddingProgress {
  total: number;
  processed: number;
  status: "idle" | "starting" | "processing" | "completed";
  percentage: number;
}

export const getEmbeddingProgress = async (
  serverId: string | number
): Promise<EmbeddingProgress> => {
  try {
    const response = await fetch(
      `${process.env.API_URL}/admin/servers/${serverId}/embedding/progress`,
      {
        method: "GET",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${await getToken()}`,
        },
        cache: "no-store",
      }
    );

    if (!response.ok) {
      console.error(
        "Failed to fetch embedding progress:",
        response.status,
        response.statusText
      );
      throw new Error("Failed to fetch embedding progress");
    }

    const result = await response.json();
    return result.data;
  } catch (error) {
    console.error("Error fetching embedding progress:", error);
    // Return default values on error
    return {
      total: 0,
      processed: 0,
      status: "idle",
      percentage: 0,
    };
  }
};

export async function clearEmbeddings(
  serverId: number
): Promise<{ message: string }> {
  const response = await fetch(
    `/api/admin/servers/${serverId}/clear-embeddings`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
    }
  );

  if (!response.ok) {
    const error = await response.json();
    throw new Error(error.error || "Failed to clear embeddings");
  }

  return response.json();
}
