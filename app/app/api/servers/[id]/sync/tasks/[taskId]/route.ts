import { getSyncTask } from "@/lib/db";
import { NextRequest, NextResponse } from "next/server";

export async function GET(
  request: NextRequest,
  {
    params,
  }: {
    params: {
      id: string;
      taskId: string;
    };
  }
) {
  const { id, taskId } = params;

  if (!id || !taskId) {
    return NextResponse.json({ error: "Missing id or taskId" });
  }

  const task = await getSyncTask(Number(id), Number(taskId));
  return NextResponse.json(task);
}
