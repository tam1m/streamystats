"use server";

import { NextRequest } from "next/server";

/**
 * Validates API key from Authorization header
 * Expected format: "Bearer <api-key>" or just "<api-key>"
 */
export async function validateApiKey(request: NextRequest): Promise<boolean> {
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

  // Get the expected API key from environment variable
  const expectedApiKey = process.env.STREAMYSTATS_API_KEY;
  
  if (!expectedApiKey) {
    console.error("STREAMYSTATS_API_KEY environment variable is not set");
    return false;
  }

  return apiKey === expectedApiKey;
}

/**
 * Middleware helper to check API key authentication
 * Returns null if valid, Response object if invalid
 */
export async function requireApiKey(request: NextRequest): Promise<Response | null> {
  const isValid = await validateApiKey(request);
  
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