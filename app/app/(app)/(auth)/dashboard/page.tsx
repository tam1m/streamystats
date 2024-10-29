import { Container } from "@/components/Container";
import { PageTitle } from "@/components/PageTitle";
import { getServers, getStatistics } from "@/lib/db";
import { WatchTimeGraph } from "./WatchTimeGraph";
import { redirect } from "next/navigation";

export default async function DashboardPage() {
  const servers = await getServers();
  const server = servers?.[0];

  if (!server) {
    console.log("No server redirecting to setup...");
    redirect("/setup");
  }

  const data = await getStatistics(server.id);

  if (!data) {
    redirect("/settings");
  }

  return (
    <Container>
      <PageTitle title="Statistics" />
      <WatchTimeGraph data={data.watchtime_per_day} />
    </Container>
  );
}
