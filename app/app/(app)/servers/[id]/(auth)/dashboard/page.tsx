import { Container } from "@/components/Container";
import { PageTitle } from "@/components/PageTitle";
import { getServer } from "@/lib/db";
import { addDays } from "date-fns";
import { redirect } from "next/navigation";
import { Suspense } from "react";
import { ActiveSessionsWithSuspense } from "./ActiveSessionsWithSuspense";
import Graph from "./Graph";
import LoadingSessions from "./LoadingSessions";
import StatsWithSuspense from "./StatsWithSuspense";
import { Skeleton } from "@/components/ui/skeleton";

export default async function DashboardPage({
  params,
  searchParams,
}: {
  params: Promise<{ id: string }>;
  searchParams: Promise<{ startDate: string; endDate: string }>;
}) {
  const { id } = await params;
  const { startDate, endDate } = await searchParams;
  const server = await getServer(id);

  if (!server) {
    // User has not added a server yet
    redirect("/setup");
  }

  let _startDate = startDate;
  let _endDate = endDate;
  if (!startDate || !endDate) {
    _startDate = addDays(new Date(), -30).toISOString().split("T")[0];
    _endDate = new Date().toISOString().split("T")[0];

    redirect(
      `/servers/${id}/dashboard?startDate=${_startDate}&endDate=${_endDate}`
    );
  }

  return (
    <Container>
      <PageTitle title="Statistics" />
      <div className="flex flex-col gap-4">
        <Suspense fallback={<LoadingSessions />}>
          <ActiveSessionsWithSuspense server={server} />
        </Suspense>

        <Suspense fallback={<Skeleton className="h-48 w-full" />}>
          <StatsWithSuspense
            server={server}
            startDate={_startDate}
            endDate={_endDate}
          />
        </Suspense>

        <Suspense fallback={<Skeleton className="h-48 w-full" />}>
          <Graph server={server} startDate={_startDate} endDate={_endDate} />
        </Suspense>
      </div>
    </Container>
  );
}
