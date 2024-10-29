import { getServers } from "@/lib/db";
import { redirect } from "next/navigation";

export default async function Home() {
  const servers = await getServers();
  const apiKey = servers?.[0]?.api_key;

  if (!apiKey) {
    redirect("/setup");
  } else {
    redirect("/dashboard");
  }
}
