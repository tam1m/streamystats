import { getServers } from "@/lib/db";
import { getPreferredServer } from "@/lib/preferred-server";
import { redirect } from "next/navigation";

export default async function Home() {
  const servers = await getServers();
  const preferredServerId = await getPreferredServer();

  // If no servers exist, redirect to setup
  if (servers.length === 0) {
    redirect("/setup");
  }

  // If we have a preferred server and it exists in the available servers, use it
  if (preferredServerId) {
    const preferredServer = servers.find(
      (server) => server.id === preferredServerId
    );
    if (preferredServer) {
      redirect(`/servers/${preferredServer.id}/dashboard`);
    }
  }

  // Fallback to the first available server
  redirect(`/servers/${servers[0].id}/dashboard`);
}
