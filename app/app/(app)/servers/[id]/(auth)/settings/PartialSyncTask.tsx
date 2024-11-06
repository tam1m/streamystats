"use client";

import { Spinner } from "@/components/Spinner";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";
import { getSyncTasks, Server, syncFullTask, syncPartialTask } from "@/lib/db";
import { isTaskRunning, taskLastRunAt } from "@/lib/utils";
import { useQuery } from "@tanstack/react-query";
import { useCallback, useMemo } from "react";
import { toast } from "sonner";

interface Props {
  server: Server;
}

export const PartialSyncTask: React.FC<Props> = ({ server }) => {
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

  const lastRun = useMemo(() => taskLastRunAt(data, "partial_sync"), [data]);

  const action = useCallback(async () => {
    try {
      await syncPartialTask(server.id);
      toast.success("Task started");
    } catch (error) {
      toast.error("Failed to start task");
    }
  }, [server]);

  if (isLoading) return <Skeleton className="w-full h-[76px] rounded-lg" />;

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
