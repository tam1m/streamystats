"use client";

import { Spinner } from "@/components/Spinner";
import { Button } from "@/components/ui/button";
import { Server, syncFullTask, syncPartialTask } from "@/lib/db";
import { useCallback } from "react";
import { toast } from "sonner";

interface Props {
  server: Server;
  running?: boolean;
  lastRun?: Date;
}

export const PartialSyncTask: React.FC<Props> = ({
  server,
  running = false,
  lastRun,
}) => {
  const action = useCallback(async () => {
    try {
      await syncPartialTask(server.id);
      toast.success("Task started");
    } catch (error) {
      toast.error("Failed to start task");
    }
  }, [server]);

  return (
    <div className="flex flex-row items-center justify-between mb-4 gap-4">
      <div>
        <p className="font-semibold">Partial sync task</p>
        <p className="text-sm">
          Syncs all users, libraries and watch statistics from your Jellyfin
          server.
        </p>
        <p className="text-xs text-neutral-500">
          Last run: {lastRun?.toLocaleString() ?? "Never"}
        </p>
      </div>
      <Button
        disabled={running}
        onClick={() => {
          action();
        }}
        variant={"outline"}
      >
        {running ? <Spinner /> : "Run"}
      </Button>
    </div>
  );
};
