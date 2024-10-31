"use server";

import { Container } from "@/components/Container";
import { Button } from "@/components/ui/button";
import { getMe, getServer, getServers, getUser, Server } from "@/lib/db";
import { toast } from "sonner";
import { FullSyncTask } from "./FullSyncTask";
import { PartialSyncTask } from "./PartialSyncTask";
import { UsersSyncTask } from "./UsersSyncTask";
import { Separator } from "@/components/ui/separator";
import { LibrariesSyncTask } from "./LibrariesSyncTask";
import { redirect } from "next/navigation";
import { DeleteServer } from "./DeleteServer";

export default async function Settings({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const server = await getServer(id);

  const me = await getMe();
  const user = await getUser(me?.name, server?.id);

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
