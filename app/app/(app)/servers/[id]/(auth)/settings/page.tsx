"use server";

import { Container } from "@/components/Container";
import { getServer } from "@/lib/db";
import { redirect } from "next/navigation";
import { DeleteServer } from "./DeleteServer";
import JellystatsImport from "./JellystatsImport";
import { Tasks } from "./Tasks";
import { VersionSection } from "./VersionSection";

export default async function Settings({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const server = await getServer(id);

  if (!server) {
    redirect("/setup");
  }

  return (
    <Container className="">
      <h1 className="text-3xl font-bold mb-8">Settings</h1>
      <Tasks server={server} />
      <div className="mb-4">
        <h2 className="text-2xl font-semibold mb-4">Jellystat import</h2>
        <JellystatsImport serverId={server.id} />
      </div>
      <VersionSection />
      <DeleteServer server={server} />
    </Container>
  );
}
