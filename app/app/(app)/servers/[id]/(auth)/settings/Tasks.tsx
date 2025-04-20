"use client";

import { Server } from "@/lib/db";
import { Separator } from "@radix-ui/react-separator";
import { DeleteServer } from "./DeleteServer";
import { FullSyncTask } from "./FullSyncTask";
import { LibrariesSyncTask } from "./LibrariesSyncTask";
import { UsersSyncTask } from "./UsersSyncTask";

interface TasksProps {
  server: Server;
}

export const Tasks: React.FC<TasksProps> = ({ server }) => {
  return (
    <div className="flex flex-col gap-2">
      <FullSyncTask server={server} />
      <UsersSyncTask server={server} />
      <LibrariesSyncTask server={server} />
    </div>
  );
};
