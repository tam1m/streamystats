"use client";

import { Button } from "@/components/ui/button";
import { Server, syncLibrariesTask, syncUsersTask } from "@/lib/db";
import { useCallback } from "react";
import { toast } from "sonner";

interface Props {
  server: Server;
}

export const LibrariesSyncTask: React.FC<Props> = ({ server }) => {
  const action = useCallback(async () => {
    try {
      await syncLibrariesTask(server.id);
      toast.success("Task started");
    } catch (error) {
      toast.error("Failed to start task");
    }
  }, [server]);

  return (
    <div className="flex flex-row items-center justify-between mb-4 gap-4">
      <div>
        <p className="font-semibold">Sync libraries</p>
        <p className="text-sm">
          Sync libraries from the server to the database.
        </p>
      </div>
      <Button
        onClick={() => {
          action();
        }}
        variant={"outline"}
      >
        Run
      </Button>
    </div>
  );
};
