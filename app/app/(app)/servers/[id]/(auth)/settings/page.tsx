"use server";

import { Container } from "@/components/Container";
import { Button } from "@/components/ui/button";
import { getMe, getServers, getUser, Server } from "@/lib/db";
import { toast } from "sonner";
import { FullSyncTask } from "./FullSyncTask";
import { PartialSyncTask } from "./PartialSyncTask";
import { UsersSyncTask } from "./UsersSyncTask";
import { Separator } from "@/components/ui/separator";
import { LibrariesSyncTask } from "./LibrariesSyncTask";
import { redirect } from "next/navigation";
import { DeleteServer } from "./DeleteServer";

export default async function Settings() {
  const servers: Server[] = await getServers();
  const server = servers?.[0];

  const me = await getMe();
  const user = await getUser(me?.name, server.id);

  if (!server) {
    redirect("/setup");
  }

  return (
    <Container>
      <h1 className="text-3xl font-bold mb-8">Tasks</h1>
      <FullSyncTask server={server} />
      <PartialSyncTask server={server} />
      <Separator className="my-8" />
      <UsersSyncTask server={server} />
      <LibrariesSyncTask server={server} />
      <Separator className="my-8" />
      {user?.is_administrator && <DeleteServer server={server} />}
    </Container>
  );
}
