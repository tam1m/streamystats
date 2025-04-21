"use server";

import { revalidatePath } from "next/cache";
import { getToken } from "./token";

type State = {
  type: "success" | "error" | "info" | null;
  message: string;
};

/**
 * Import database backup file from SQLite .db file
 */
export const importDatabaseBackup = async (
  prevState: State,
  formData: FormData
): Promise<State> => {
  console.log("Starting database backup import process");

  const file = formData.get("file") as File | null;
  const serverId = formData.get("serverId") as string;

  console.log(`Import request received for server: ${serverId}`);

  if (!file) {
    console.error("Import failed: No file selected");
    return { type: "error", message: "No file selected" };
  }

  if (!serverId) {
    console.error("Import failed: Server ID is missing");
    return { type: "error", message: "Server ID is missing" };
  }

  try {
    console.log(`Processing file: ${file.name} (${file.size} bytes)`);

    // Validate file type
    if (!file.name.endsWith(".db")) {
      console.error(`Import failed: Invalid file type - ${file.name}`);
      return {
        type: "error",
        message: "Invalid file type. Please select a .db file.",
      };
    }

    // Prepare FormData for API request
    const apiFormData = new FormData();
    apiFormData.append("file", file);
    console.log("FormData prepared for API request");

    // Get token for authentication
    const token = await getToken();
    if (!token) {
      console.error("Import failed: Authentication token not available");
      return {
        type: "error",
        message: "Not authenticated. Please log in again.",
      };
    }

    console.log(
      `Making API request to ${process.env.API_URL}/servers/${serverId}/backup/import`
    );

    // Make API request to backend
    const response = await fetch(
      `${process.env.API_URL}/servers/${serverId}/backup/import`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${token}`,
        },
        body: apiFormData,
      }
    );

    console.log(`API response status: ${response.status}`);

    if (!response.ok) {
      const errorData = await response.json().catch(() => {
        console.error("Failed to parse error response");
        return { error: "Unknown error occurred" };
      });

      console.error("Import failed with API error:", errorData);
      return {
        type: "error",
        message:
          errorData.error ||
          "Failed to import database backup. Please try again.",
      };
    }

    console.log("Database import successful, revalidating path");
    revalidatePath(`/servers/${serverId}/settings`);

    console.log("Database import process completed successfully");
    return {
      type: "success",
      message:
        "Your database backup has been successfully imported! The system has updated with the imported playback sessions.",
    };
  } catch (error) {
    console.error("Error uploading database backup:", error);
    return {
      type: "error",
      message:
        error instanceof Error
          ? error.message
          : "An unexpected error occurred. Please try again.",
    };
  }
};

/**
 * Export database as SQLite .db file
 * Note: This functions differently than import as it needs to return
 * a download URL rather than process a form upload
 */
export const exportDatabaseBackup = async (
  serverId: string
): Promise<{
  success: boolean;
  error?: string;
  url?: string;
  filename?: string;
}> => {
  console.log(
    `Starting database backup export process for server: ${serverId}`
  );

  try {
    // Get the token for authentication
    console.log("Retrieving authentication token");
    const token = await getToken();

    if (!token) {
      console.error("Export failed: Authentication token not available");
      return {
        success: false,
        error: "Not authenticated. Please log in again.",
      };
    }

    // Make API request to get the export
    const exportUrl = `${process.env.API_URL}/servers/${serverId}/backup/export`;
    console.log(`Making API request to ${exportUrl}`);

    const response = await fetch(exportUrl, {
      method: "GET",
      headers: {
        Authorization: `Bearer ${token}`,
      },
    });

    console.log(`API response status: ${response.status}`);
    if (!response.ok) {
      const errorData = await response.json().catch(() => {
        console.error("Failed to parse error response");
        return { error: "Error generating export" };
      });

      console.error("Export failed with API error:", errorData);
      return {
        success: false,
        error:
          errorData.error || "Failed to export database. Please try again.",
      };
    }

    // Get the filename from Content-Disposition header
    const contentDisposition = response.headers.get("Content-Disposition");
    let filename = "playback_sessions_backup.db";

    if (contentDisposition) {
      const match = contentDisposition.match(/filename="?([^"]+)"?/);
      if (match?.[1]) {
        filename = match[1];
      }
    }
    console.log(`Using filename for export: ${filename}`);

    // Convert response to Blob
    console.log("Converting response to Blob");
    const blob = await response.blob();
    console.log(`Retrieved data blob of size: ${blob.size} bytes`);

    // Create a local URL for the blob
    const url = URL.createObjectURL(blob);
    console.log("Created object URL for download");

    console.log("Database export process completed successfully", {
      url,
      filename,
    });
    return {
      success: true,
      url,
      filename,
    };
  } catch (error) {
    console.error("Error exporting database:", error);
    return {
      success: false,
      error:
        error instanceof Error
          ? error.message
          : "An unexpected error occurred. Please try again.",
    };
  }
};
