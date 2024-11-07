import { clsx, type ClassValue } from "clsx";
import { twMerge } from "tailwind-merge";
import { SyncTask } from "./db";

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

export function formatDuration(
  t: number,
  unit: "seconds" | "minutes" = "seconds"
): string {
  if (t === 0) return "0m";

  let totalSeconds = unit === "minutes" ? t * 60 : t;
  const hours = Math.floor(totalSeconds / 3600);
  const minutes = Math.floor((totalSeconds % 3600) / 60);
  const seconds = Math.floor(totalSeconds % 60);

  let formattedDuration = "";

  if (hours > 0) {
    formattedDuration += `${hours}h `;
  }

  if (hours > 0 || minutes > 0) {
    formattedDuration += `${minutes}m`;
  }

  if (unit === "seconds" && hours === 0 && minutes === 0) {
    formattedDuration += `${seconds}s`;
  }

  return formattedDuration.trim();
}

export const isTaskRunning = (
  data?: SyncTask[] | null,
  type?: SyncTask["sync_type"] | null
): boolean => {
  if (!type) return false;
  if (!data) return false;

  return data?.some((task) => {
    if (!task.sync_started_at) return false;

    const taskStartTime = new Date(task.sync_started_at);
    const currentTime = new Date();

    return (
      taskStartTime.getTime() <= currentTime.getTime() &&
      task.sync_type === type &&
      !task.sync_completed_at
    );
  });
};

export const taskLastRunAt = (
  data?: SyncTask[] | null,
  type?: SyncTask["sync_type"] | null
): string => {
  if (!type) return "Never";
  if (!data) return "Never";

  const d = data?.find((task) => task.sync_type === type)?.sync_completed_at;
  if (!d) return "Never";

  const utcDate = new Date(d);
  return new Date(
    utcDate.getTime() - utcDate.getTimezoneOffset() * 60000
  ).toLocaleString();
};
