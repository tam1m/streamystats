import { getServers } from "@/lib/db";
import { redirect } from "next/navigation";

export default async function Home() {
  const servers = await getServers();
  if (servers.length === 0) redirect("/setup");
  else redirect(`/servers/${servers[0].id}/dashboard`);
}
