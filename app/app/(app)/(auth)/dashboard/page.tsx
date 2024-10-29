import { redirect } from "next/navigation";
import { Dashboard } from "./Dashboard";
import { getServers, getStatistics } from "@/lib/db";
import { Container } from "@/components/Container";
import { WatchTimeGraph } from "./WatchTimeGraph";
import { MostPopularItem } from "./MostPopularItem";
import { unstable_noStore } from "next/cache";
import { PageTitle } from "@/components/PageTitle";

export default async function DashboardPage() {
  const servers = await getServers();
  const server = servers[0];
  const data = await getStatistics(server.id);
  return (
    <Container>
      <PageTitle title="Statistics" />
      <WatchTimeGraph data={data.watchtime_per_day} />
    </Container>
  );
}
