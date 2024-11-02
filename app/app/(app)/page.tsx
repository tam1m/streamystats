import { getServers } from "@/lib/db";
import { redirect } from "next/navigation";

export default async function Home() {
  const servers = await getServers();

  // TODO: figure out why server id is null sometimes?
  if (servers?.[0]?.id) {
    redirect(`/servers/${servers[0].id}/dashboard`);
  } else {
    redirect("/setup");
  }
}
