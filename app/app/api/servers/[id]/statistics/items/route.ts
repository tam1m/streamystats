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
  const search = searchParams.get("search");
  const page = searchParams.get("page");
  const sort_by = searchParams.get("sort_by");
  const sort_order = searchParams.get("sort_order");
  const { id } = params;

  const queryParams = new URLSearchParams({
    page: (page || 1).toString(),
  });

  if (search && search.length > 0) {
    queryParams.append("search", search);
  }

  if (sort_by && sort_by.length > 0 && sort_order && sort_order.length > 0) {
    queryParams.append("sort_by", sort_by);
    queryParams.append("sort_order", sort_order);
  }

  const res = await fetch(
    `${
      process.env.API_URL
    }/servers/${id}/statistics/items?${queryParams.toString()}`,
    {
      next: {
        revalidate: 0,
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
