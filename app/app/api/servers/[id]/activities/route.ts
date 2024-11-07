import { getToken } from "@/lib/token";
import { NextRequest, NextResponse } from "next/server";

export async function GET(
  request: NextRequest,
  {
    params,
  }: {
    params: {
      id: string;
    };
  }
) {
  const searchParams = request.nextUrl.searchParams;
  const page = searchParams.get("page");
  const { id } = params;

  const queryParams = new URLSearchParams({
    page: (page || 1).toString(),
  });

  const res = await fetch(
    `${
      process.env.API_URL
    }/admin/servers/${id}/activities?${queryParams.toString()}`,
    {
      next: {
        revalidate: 60 * 1, // 1 minutes
      },
      headers: {
        Authorization: `Bearer ${await getToken()}`,
        "Content-Type": "application/json",
      },
    }
  );

  const data = await res.json();

  return NextResponse.json(data);
}
