import { Container } from "@/components/Container";
import { PageTitle } from "@/components/PageTitle";
import { Skeleton } from "@/components/ui/skeleton";
import { getServer, Server, Statistics } from "@/lib/db";
import { addDays } from "date-fns";
import { redirect } from "next/navigation";
import { Suspense } from "react";
import Graph from "../Graph";
import TotalWatchTime from "../TotalWatchTime";
import { WatchTimePerWeekDay } from "../WatchTimePerWeekDay";
import { WatchTimePerHour } from "../WatchTimePerHour";

interface ServerWithStats extends Server {
  statistics?: Statistics;
}

export default async function WatchtimePage({
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

  // Calculate default dates without redirecting
  const _startDate =
    startDate || addDays(new Date(), -30).toISOString().split("T")[0];
  const _endDate = endDate || new Date().toISOString().split("T")[0];

  return (
    <Container>
      <PageTitle title="Watchtime Statistics" />
      <Suspense fallback={<Skeleton className="h-48 w-full" />}>
        <WatchtimeStats
          server={server}
          startDate={_startDate}
          endDate={_endDate}
        />
      </Suspense>
    </Container>
  );
}

async function WatchtimeStats({
  server,
  startDate,
  endDate,
}: {
  server: Server;
  startDate: string;
  endDate: string;
}) {
  const serverWithStats = (await getServer(server.id)) as ServerWithStats;

  return (
    <div className="flex flex-col gap-6">
      <div className="flex md:flex-row flex-col gap-2">
        <TotalWatchTime
          data={serverWithStats?.statistics?.total_watch_time || 0}
        />
      </div>
      <Suspense fallback={<Skeleton className="h-48 w-full" />}>
        <Graph server={server} startDate={startDate} endDate={endDate} />
      </Suspense>
      <Suspense fallback={<Skeleton className="h-48 w-full" />}>
        <WatchTimePerWeekDay
          data={serverWithStats?.statistics?.watchtime_per_week_day || []}
          title="Watch Time Per Day of Week"
          subtitle="Showing total watch time for each day of the week"
        />
      </Suspense>
      <Suspense fallback={<Skeleton className="h-48 w-full" />}>
        <WatchTimePerHour
          data={serverWithStats?.statistics?.watchtime_per_hour || []}
          title="Watch Time Per Hour"
          subtitle="Showing total watch time for each hour of the day"
        />
      </Suspense>
    </div>
  );
}
