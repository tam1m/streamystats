import { Container } from "@/components/Container";
import { PageTitle } from "@/components/PageTitle";
import { Skeleton } from "@/components/ui/skeleton";
import { getServer, Server, Statistics, MostWatchedItem } from "@/lib/db";
import { isUserAdmin } from "@/lib/me";
import { addDays } from "date-fns";
import { redirect } from "next/navigation";
import { Suspense } from "react";
import { ActiveSessions } from "./ActiveSessions";
import { getSimilarStatistics } from "@/lib/db/similar-statistics";
import { SimilarStatstics } from "./SimilarStatstics";
import { MostWatchedItems } from "./MostWatchedItems";
import { UserLeaderboard } from "./UserLeaderboard";

interface ServerWithStats extends Server {
  statistics?: Statistics;
}

export default async function DashboardPage({
  params,
  searchParams,
}: {
  params: Promise<{ id: string }>;
  searchParams: Promise<{
    startDate: string;
    endDate: string;
  }>;
}) {
  const { id } = await params;
  const { startDate, endDate } = await searchParams;
  const server = await getServer(id);

  if (!server) {
    redirect("/not-found");
  }

  const isAdmin = await isUserAdmin();

  // Calculate default dates without redirecting
  const _startDate =
    startDate || addDays(new Date(), -30).toISOString().split("T")[0];
  const _endDate = endDate || new Date().toISOString().split("T")[0];

  return (
    <Container>
      {isAdmin && (
        <div className="mb-8">
          <ActiveSessions server={server} />
        </div>
      )}
      <PageTitle title="General Statistics" />
      <Suspense fallback={<Skeleton className="h-48 w-full" />}>
        <GeneralStats
          server={server}
          startDate={_startDate}
          endDate={_endDate}
        />
      </Suspense>
    </Container>
  );
}

async function GeneralStats({
  server,
  startDate,
  endDate,
}: {
  server: Server;
  startDate: string;
  endDate: string;
}) {
  const data = await getSimilarStatistics(server.id);
  const isAdmin = await isUserAdmin();
  const serverWithStats = (await getServer(server.id)) as ServerWithStats;

  const mostWatchedItems = {
    Movie: [] as MostWatchedItem[],
    Episode: [] as MostWatchedItem[],
    Series: [] as MostWatchedItem[],
  };

  if (serverWithStats?.statistics?.most_watched_items) {
    mostWatchedItems.Movie =
      serverWithStats.statistics.most_watched_items.Movie || [];
    mostWatchedItems.Episode =
      serverWithStats.statistics.most_watched_items.Episode || [];
    mostWatchedItems.Series =
      serverWithStats.statistics.most_watched_items.Series || [];
  }

  return (
    <div className="flex flex-col gap-6">
      <SimilarStatstics data={data} server={server} />
      <Suspense fallback={<Skeleton className="h-48 w-full" />}>
        <MostWatchedItems data={mostWatchedItems} server={server} />
      </Suspense>
      {isAdmin ? <UserLeaderboard server={server} /> : null}
    </div>
  );
}
