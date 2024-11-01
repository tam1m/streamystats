import { getSyncTasks } from "@/lib/db";
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
  const { id } = params;

  if (!id) {
    return NextResponse.json({ error: "Missing id" });
  }

  const tasks = await getSyncTasks(Number(id));
  return NextResponse.json(tasks);
}
