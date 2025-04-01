import { getToken } from "@/lib/token";
import { NextRequest, NextResponse } from "next/server";

export async function GET(request: NextRequest) {
  try {
    const { searchParams } = new URL(request.url);

    // Extract Jellyfin-specific parameters
    const serverId = searchParams.get("serverId");
    const itemId = searchParams.get("itemId");
    const imageTag = searchParams.get("imageTag");

    // Use the exact same query parameter names as Jellyfin
    const fillWidth = searchParams.get("width") || "368";
    const fillHeight = searchParams.get("height") || "552";
    const quality = searchParams.get("quality") || "96";
    const type = searchParams.get("type") || "Primary";

    console.log("Image proxy request params:", {
      serverId,
      itemId,
      imageTag,
      type,
    });

    if (!serverId || !itemId || !imageTag) {
      return new NextResponse("Missing required parameters", { status: 400 });
    }

    // Get server URL from your database
    const serverResponse = await fetch(
      `${process.env.API_URL}/servers/${serverId}`,
      {
        headers: {
          Authorization: `Bearer ${await getToken()}`,
        },
      }
    );

    if (!serverResponse.ok) {
      console.error(`Server not found: ${serverResponse.status}`);
      return new NextResponse("Server not found", { status: 404 });
    }

    const server = await serverResponse.json();
    console.log("Server info:", {
      id: server.id,
      name: server.name,
      url: server.url,
      hasApiKey: !!server.api_key,
    });

    // Ensure server URL is defined and properly formatted
    if (!server.url) {
      console.error("Server URL is undefined");
      return new NextResponse("Server URL is undefined", { status: 500 });
    }

    // Remove trailing slash if present
    const serverUrl = server.url.endsWith("/")
      ? server.url.slice(0, -1)
      : server.url;

    // Construct the Jellyfin image URL with EXACTLY the same format as your example
    const imageUrl = `${serverUrl}/Items/${itemId}/Images/${type}?fillHeight=${fillHeight}&fillWidth=${fillWidth}&quality=${quality}&tag=${imageTag}`;
    console.log("Jellyfin image URL:", imageUrl);

    // Fetch the image from Jellyfin
    const imageResponse = await fetch(imageUrl, {
      headers: {
        // Add any necessary headers for Jellyfin authentication
        ...(server.api_key ? { "X-Emby-Token": server.api_key } : {}),
      },
    });

    if (!imageResponse.ok) {
      console.error(`Image fetch failed: Status ${imageResponse.status}`);

      // Log the response body content to see the error message
      try {
        const errorText = await imageResponse.text();
        console.error(`Error response body: ${errorText}`);
      } catch (e) {
        console.error(`Could not read error response: ${e}`);
      }

      return new NextResponse(`Image not found: ${imageResponse.status}`, {
        status: 404,
      });
    }

    // Get the image data
    const imageData = await imageResponse.arrayBuffer();
    console.log(`Received image data: ${imageData.byteLength} bytes`);

    // Get the content type
    const contentType =
      imageResponse.headers.get("content-type") || "image/jpeg";
    console.log("Content type:", contentType);

    // Return the image with the correct content type
    return new NextResponse(imageData, {
      headers: {
        "Content-Type": contentType,
        "Cache-Control": "public, max-age=31536000, immutable",
      },
    });
  } catch (error) {
    console.error("Error proxying image:", error);
    return new NextResponse(`Internal Server Error`, {
      status: 500,
    });
  }
}
