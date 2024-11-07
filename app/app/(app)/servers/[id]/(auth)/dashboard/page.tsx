import { Container } from "@/components/Container";
import { PageTitle } from "@/components/PageTitle";
import { getServer, getStatistics, getUser } from "@/lib/db";
import { redirect } from "next/navigation";
import { MostPopularItems } from "./MostPopularItems";
import { WatchTimeGraph } from "./WatchTimeGraph";
import { WatchTimePerWeekDay } from "./WatchTimePerWeekDay";
import { getMe } from "@/lib/me";

export default async function DashboardPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const server = await getServer(id);
  const me = await getMe();
  const user = await getUser(me?.name, server?.id);

  if (!server) {
    // User has not added a server yet
    redirect("/setup");
  }

  const data = await getStatistics(server.id);

  return (
    <Container>
      <PageTitle title="Statistics" />
      {data?.most_watched_items && data.watchtime_per_day ? (
        <div className="flex flex-col gap-6">
          <MostPopularItems data={data.most_watched_items} server={server} />
          <WatchTimeGraph data={data.watchtime_per_day} />
          <WatchTimePerWeekDay data={data.average_watchtime_per_week_day} />
        </div>
      ) : (
        <div>
          <p>You don't have any statistics yet.</p>
          {user?.is_administrator ? (
            <p>
              If you know that you have watch statistics please run the full
              sync task from the settings.
            </p>
          ) : (
            <p className="text-neutral-500">
              Watch some movies or tv-shows first!
            </p>
          )}
        </div>
      )}
    </Container>
  );
}
