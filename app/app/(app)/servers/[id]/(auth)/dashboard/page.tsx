import { Container } from "@/components/Container";
import { PageTitle } from "@/components/PageTitle";
import { getServer, getStatistics } from "@/lib/db";
import { redirect } from "next/navigation";
import { MostPopularItem } from "./MostPopularItem";
import { NoStatsModal } from "./NoStatsModal";
import { WatchTimeGraph } from "./WatchTimeGraph";

export default async function DashboardPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const server = await getServer(id);

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
