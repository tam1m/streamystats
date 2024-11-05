"use client";

import { Spinner } from "@/components/Spinner";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";
import { getSyncTasks, Server, syncFullTask, SyncTask } from "@/lib/db";
import { isTaskRunning, taskLastRunAt } from "@/lib/utils";
import { useQuery } from "@tanstack/react-query";
import { useCallback, useMemo } from "react";
import { toast } from "sonner";

interface Props {
  server: Server;
}

export const FullSyncTask: React.FC<Props> = ({ server }) => {
  const { data, isLoading } = useQuery({
    queryKey: ["tasks", server.id],
    queryFn: async () => {
      return await getSyncTasks(server.id);
    },
    refetchInterval: 2000,
    staleTime: 2000,
  });

  const running = useMemo(
    () => isTaskRunning(data, "full_sync") || false,
    [data]
  );

  const lastRun = useMemo(() => taskLastRunAt(data, "full_sync"), [data]);

  const action = useCallback(async () => {
    try {
      await syncFullTask(server.id);
      toast.success("Task started");
    } catch (error) {
      toast.error("Failed to start task");
    }
  }, [server]);

  if (isLoading) return <Skeleton className="w-full h-[76px] rounded-lg" />;

  return (
    <div className="flex flex-row items-center justify-between mb-4 gap-4">
      <div className="">
        <p className="font-semibold">Full sync task</p>
        <p className="text-sm">
          Syncs all items, users, libraries and watch statistics from your
          Jellyfin server.
        </p>
        <p className="text-xs text-neutral-500">Last run: {lastRun}</p>
      </div>
      <Button
        disabled={running}
        onClick={() => {
          action();
        }}
      >
        {running ? <Spinner /> : "Run"}
      </Button>
    </div>
  );
};
