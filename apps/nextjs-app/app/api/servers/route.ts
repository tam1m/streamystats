import { getServers, createServer } from "@/lib/server";

export const dynamic = 'force-dynamic';

export async function GET() {
  try {
    const servers = await getServers();
    return new Response(JSON.stringify(servers), {
      status: 200,
      headers: {
        "Content-Type": "application/json",
      },
    });
  } catch (error) {
    console.error("Error fetching servers:", error);
    return new Response(
      JSON.stringify({
        error: "Failed to fetch servers",
      }),
      {
        status: 500,
        headers: {
          "Content-Type": "application/json",
        },
      }
    );
  }
}

export async function POST(request: Request) {
  try {
    const body = await request.json();
    const { name, url, apiKey, ...otherFields } = body;

    if (!name || !url || !apiKey) {
      return new Response(
        JSON.stringify({
          error: "Name, URL, and API key are required",
        }),
        {
          status: 400,
          headers: {
            "Content-Type": "application/json",
          },
        }
      );
    }

    const result = await createServer({ name, url, apiKey, ...otherFields });
    return new Response(JSON.stringify(result), {
      status: 201,
      headers: {
        "Content-Type": "application/json",
      },
    });
  } catch (error) {
    console.error("Error creating server:", error);
    return new Response(
      JSON.stringify({
        error:
          error instanceof Error ? error.message : "Failed to create server",
      }),
      {
        status: 500,
        headers: {
          "Content-Type": "application/json",
        },
      }
    );
  }
}
