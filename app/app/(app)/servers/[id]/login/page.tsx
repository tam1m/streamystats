import { getServer, getServers } from "@/lib/db";
import { redirect } from "next/navigation";
import { SignInForm } from "./SignInForm";

export default async function Setup({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const server = await getServer(id);
  const servers = await getServers();

  if (!server) {
    redirect("/not-found");
  }

  return <SignInForm server={server} servers={servers} />;
}
