import { Container } from "@/components/Container";
import { PageTitle } from "@/components/PageTitle";
import { Badge } from "@/components/ui/badge";
import { getServer, getStatisticsHistory, getUser } from "@/lib/db";
import { HistoryTable } from "../../history/HistoryTable";
import { formatDuration } from "@/lib/utils";
import { WatchTimePerDay } from "./WatchTimePerDay.tsx";
import { redirect } from "next/navigation";
import { GenreStatsGraph } from "./GenreStatsGraph";
import UserBadges from "./UserBadges";

export default async function User({
  params,
}: {
  params: Promise<{ id: string; name: string }>;
}) {
  const { id, name } = await params;
  const server = await getServer(id);

  if (!server) {
    redirect("/");
  }

  const user = await getUser(name, server.id);
  const data = await getStatisticsHistory(server.id);
  console.log(user);

  if (!user) {
    redirect("/");
  }

  return (
    <Container>
      <PageTitle title={user.name || "N/A"} />
      <div className="flex flex-col gap-4">
        <UserBadges user={user} />
        <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
          <div className="border rounded-lg p-4">
            <p className="text-sm">Total Plays</p>
            <p className="text-xl font-bold">{user.watch_stats.total_plays}</p>
          </div>
          <div className="border rounded-lg p-4">
            <p className="text-sm">Total Watch Time</p>
            <p className="text-xl font-bold">
              {formatDuration(user.watch_stats.total_watch_time)}
            </p>
          </div>
          <div className="border rounded-lg p-4">
            <p className="text-sm">Longest day streak</p>
            <p className="text-xl font-bold">
              {formatDuration(user.longest_streak, "days")}
            </p>
          </div>
        </div>
        <div className="grid grid-rows-2 md:grid-rows-1 md:grid-cols-2 items-center gap-2">
          <GenreStatsGraph data={user.genre_stats} className="w-full" />
          <div></div>
        </div>
      </div>
      <HistoryTable server={server} data={data} hideUserColumn />
      <WatchTimePerDay data={user.watch_time_per_day} />
    </Container>
  );
}
