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
        cache: "no-store", // Don't cache this dynamic data
      }
    );
    
    if (!response.ok) {
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
      percentage: 0
    };
  }
};
