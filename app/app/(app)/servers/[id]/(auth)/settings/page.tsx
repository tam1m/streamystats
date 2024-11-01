"use server";

import { Container } from "@/components/Container";
import { Separator } from "@/components/ui/separator";
import { getMe, getServer, getUser } from "@/lib/db";
import { redirect } from "next/navigation";
import { DeleteServer } from "./DeleteServer";
import { FullSyncTask } from "./FullSyncTask";
import { LibrariesSyncTask } from "./LibrariesSyncTask";
import { PartialSyncTask } from "./PartialSyncTask";
import { UsersSyncTask } from "./UsersSyncTask";
import { Tasks } from "./Tasks";

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
    <Container className="">
      <h1 className="text-3xl font-bold mb-8">Settings</h1>
      {user?.is_administrator ? (
        <Tasks server={server} />
      ) : (
        <p>You are not an administrator of this server.</p>
      )}
    </Container>
  );
}
