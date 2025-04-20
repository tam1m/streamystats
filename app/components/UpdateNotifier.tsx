"use client";

import { useCallback, useEffect } from "react";
import { toast } from "sonner";

interface VersionInfo {
  currentVersion: string;
  latestVersion: string;
  hasUpdate: boolean;
}

export function UpdateNotifier() {
  const notifyUserOfUpdate = useCallback((newVersion: string) => {
    toast.warning(
      `A new version (${newVersion}) is available. Please update the docker image.`,
      {
        duration: Number.POSITIVE_INFINITY,
        cancel: (
          <button
            className="shrink-0 ml-2 hover:opacity-50"
            type="button"
            onClick={() => toast.dismiss()}
          >
            Dismiss
          </button>
        ),
        action: (
          <button
            type="button"
            className="shrink-0 ml-2 hover:opacity-50"
            onClick={() => {
              // Go to latest release
              window.open(
                "https://github.com/fredrikburmester/streamystats/releases/latest",
                "_blank"
              );
              toast.dismiss();
            }}
          >
            Show
          </button>
        ),
      }
    );
  }, []);

  useEffect(() => {
    // biome-ignore lint/style/useConst: <explanation>
    let intervalId: NodeJS.Timeout;

    // Function to check for updates
    const checkForUpdates = async () => {
      try {
        const response = await fetch("/api/version");
        const versionInfo: VersionInfo = await response.json();

        if (versionInfo.hasUpdate) {
        }
        notifyUserOfUpdate(versionInfo.latestVersion);
      } catch (error) {
        console.error("Failed to check for updates:", error);
      }
    };

    // Check for updates every 15 minutes
    intervalId = setInterval(checkForUpdates, 15 * 60 * 1000);

    // Initial check (with a slight delay to not impact page load)
    setTimeout(checkForUpdates, 1000);

    return () => clearInterval(intervalId);
  }, [notifyUserOfUpdate]);

  return null;
}
