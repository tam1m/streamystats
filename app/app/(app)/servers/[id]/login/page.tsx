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
    redirect("/");
  }

  return (
    <div className="grid md:grid-cols-2 h-screen w-screen">
      <Container className="justify-center bg-neutral-900 hidden md:flex">
        <h1 className="font-bold text-5xl bg-clip-text text-transparent bg-gradient-to-r from-blue-500 via-teal-500 to-purple-500 leading-[100px]">
          Streamystats
        </h1>
        <p>Track your Jellyfin stats and view them in a dashboard.</p>
      </Container>
      <Container className="md:justify-center">
        <ServerSelector servers={servers} className="mb-4 max-w-64" />
        <SignInForm server={server} />
      </Container>
    </div>
  );
}
