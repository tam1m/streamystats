import { getStatistics } from "@/lib/db";
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
  const data = await getStatistics(parseInt(params.id));
  return NextResponse.json(data);
}
