"use client";

import { Button } from "@/components/ui/button";
import { Server, syncFullTask, syncPartialTask } from "@/lib/db";
import { useCallback } from "react";
import { toast } from "sonner";

interface Props {
  server: Server;
}

export const FullSyncTask: React.FC<Props> = ({ server }) => {
  const action = useCallback(async () => {
    try {
      await syncFullTask(server.id);
      toast.success("Task started");
    } catch (error) {
      toast.error("Failed to start task");
    }
  }, [server]);

  return (
    <div className="flex flex-row items-center justify-between mb-4 gap-4">
      <div className="">
        <p className="font-semibold">Full sync task</p>
        <p className="text-sm">
          Syncs all items, users, libraries and watch statistics from your
          Jellyfin server.
        </p>
      </div>
      <Button
        onClick={() => {
          action();
        }}
      >
        Run
      </Button>
    </div>
  );
};
