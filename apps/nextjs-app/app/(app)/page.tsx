import { getServers } from "@/lib/server";
import { redirect } from "next/navigation";

// Force dynamic rendering to avoid build-time database access
export const dynamic = "force-dynamic";

export default async function Home() {
  try {
    const servers = await getServers();

    if (servers?.[0]?.id) {
      redirect(`/servers/${servers[0].id}/dashboard`);
    } else {
      redirect("/setup");
    }
  } catch (error) {
    console.error("Error fetching servers:", error);
    redirect("/setup");
  }
}
