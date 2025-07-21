"use server";

import { NextRequest } from "next/server";
import { getServer } from "./db/server";

/**
 * Validates API key from Authorization header against the specific server's API key
 * Expected format: "Bearer <api-key>" or just "<api-key>"
 */
export async function validateApiKey({ request, serverId }: { request: NextRequest; serverId: number; }): Promise<boolean> {
  const authHeader = request.headers.get("authorization");
  
  if (!authHeader) {
    return false;
  }

  // Extract API key from Authorization header
  let apiKey: string;
  if (authHeader.startsWith("Bearer ")) {
    apiKey = authHeader.substring(7);
  } else {
    apiKey = authHeader;
  }

  try {
    // Get the server from database to compare API keys
    const server = await getServer({ serverId });
    
    if (!server) {
      console.error(`Server with ID ${serverId} not found`);
      return false;
    }

    return apiKey === server.apiKey;
  } catch (error) {
    console.error("Error validating API key:", error);
    return false;
  }
}

/**
 * Middleware helper to check API key authentication for a specific server
 * Returns null if valid, Response object if invalid
 */
export async function requireApiKey({ request, serverId }: { request: NextRequest; serverId: number; }): Promise<Response | null> {
  const isValid = await validateApiKey({ request, serverId });
  
  if (!isValid) {
    return new Response(
      JSON.stringify({
        error: "Unauthorized",
        message: "Valid API key required in Authorization header",
      }),
      {
        status: 401,
        headers: {
          "Content-Type": "application/json",
        },
      }
    );
  }
  
  return null;
}