import { clsx, type ClassValue } from "clsx";
import { twMerge } from "tailwind-merge";

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

export function formatDuration(
  t: number,
  unit: "seconds" | "minutes" = "seconds"
): string {
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
