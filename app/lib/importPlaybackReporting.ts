"use server";

import { revalidatePath } from "next/cache";
import { getToken } from "./token";

type State = {
  type: "success" | "error" | "info" | null;
  message: string;
};

export const importPlaybackReporting = async (
  prevState: State,
  formData: FormData
): Promise<State> => {
  const file = formData.get("file") as File | null;
  const serverId = formData.get("serverId") as string;

  if (!file) {
    return { type: "error", message: "No file selected" };
  }

  if (!serverId) {
    return { type: "error", message: "Server ID is missing" };
  }

  try {
    // Validate file type (accepts JSON and TSV files)
    const isJson =
      file.type === "application/json" || file.name.endsWith(".json");
    const isTsv =
      file.type === "text/tab-separated-values" ||
      file.name.endsWith(".tsv") ||
      file.name.endsWith(".txt");

    if (!isJson && !isTsv) {
      return {
        type: "error",
        message: "Invalid file type. Please select a JSON or TSV file.",
      };
    }

    // Prepare FormData for API request
    const apiFormData = new FormData();
    apiFormData.append("file", file);

    // Make API request to backend
    const response = await fetch(
      `${process.env.API_URL}/admin/servers/${serverId}/playback-reporting/import`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${await getToken()}`,
        },
        body: apiFormData,
      }
    );

    if (!response.ok) {
      const errorData = await response.json();
      return {
        type: "error",
        message:
          errorData.error ||
          "Failed to import Playback Reporting data. Please try again.",
      };
    }

    // Successful response
    revalidatePath(`/servers/${serverId}/settings`);

    return {
      type: "success",
      message:
        "Your Playback Reporting data is being imported! This process runs in the background and may take several minutes depending on the amount of data.",
    };
  } catch (error) {
    console.error("Error uploading Playback Reporting data:", error);
    return {
      type: "error",
      message:
        error instanceof Error
          ? error.message
          : "An unexpected error occurred. Please try again.",
    };
  }
};
