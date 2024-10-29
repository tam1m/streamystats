"use server";

import { Container } from "@/components/Container";
import { Button } from "@/components/ui/button";
import { getServers, Server } from "@/lib/db";
import { toast } from "sonner";
import { FullSyncTask } from "./FullSyncTask";
import { PartialSyncTask } from "./PartialSyncTask";
import { UsersSyncTask } from "./UsersSyncTask";
import { Separator } from "@/components/ui/separator";
import { LibrariesSyncTask } from "./LibrariesSyncTask";

export default async function Settings() {
  const servers: Server[] = await getServers();
  const server = servers[0];

  return (
    <Container>
      <h1 className="text-3xl font-bold mb-8">Tasks</h1>
      <FullSyncTask server={server} />
      <PartialSyncTask server={server} />
      <Separator className="my-8" />
      <UsersSyncTask server={server} />
      <LibrariesSyncTask server={server} />
    </Container>
  );
}
