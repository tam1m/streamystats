import { Container } from "@/components/Container";
import { PageTitle } from "@/components/PageTitle";
import { getServers, getStatistics } from "@/lib/db";
import { WatchTimeGraph } from "./WatchTimeGraph";
import { redirect } from "next/navigation";
import { MostPopularItem } from "./MostPopularItem";
import { NoStatsModal } from "./NoStatsModal";

export default async function DashboardPage() {
  const servers = await getServers();
  const server = servers?.[0];

  if (!server) {
    // User has not added a server yet
    redirect("/setup");
  }

  const data = await getStatistics(server.id);

  return (
    <Container>
      <PageTitle title="Statistics" />
      {data?.most_watched_item && data.watchtime_per_day ? (
        <div className="flex flex-col gap-6">
          <MostPopularItem data={data.most_watched_item} />
          <WatchTimeGraph data={data.watchtime_per_day} />
        </div>
      ) : (
        <NoStatsModal />
      )}
    </Container>
  );
}
