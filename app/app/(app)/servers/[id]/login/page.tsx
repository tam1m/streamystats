import { redirect } from "next/navigation";
import { getServer, getServers } from "@/lib/db";
import { SignInForm } from "./SignInForm";
import { ServerSelector } from "@/components/ServerSelector";
import { Container } from "@/components/Container";

export default async function Setup({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const servers = await getServers();
  const server = await getServer(id);

  if (!server) {
    redirect("/not-found");
  }

  return <SignInForm server={server} />;
}
