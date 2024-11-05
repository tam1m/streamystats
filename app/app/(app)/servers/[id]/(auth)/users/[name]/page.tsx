import { Container } from "@/components/Container";
import { PageTitle } from "@/components/PageTitle";
import { Badge } from "@/components/ui/badge";
import { getServer, getUser } from "@/lib/db";
import { HistoryTable } from "../../history/HistoryTable";
import { formatDuration } from "@/lib/utils";
import { WatchTimePerDay } from "./WatchTimePerDay.tsx";
import { redirect } from "next/navigation";
import { GenreStatsGraph } from "./GenreStatsGraph";

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

  if (!user) {
    redirect("/");
  }

  console.log("genre_stats", user.genre_stats);

  return (
    <Container>
      <PageTitle title={user.name || "N/A"} />
      <div className="flex flex-col gap-4">
        <div className="flex flex-row items-center gap-2">
          <Badge className="self-start" variant="secondary">
            ID: {user.id}
          </Badge>
          <Badge className="self-start" variant="secondary">
            Jellyfin ID: {user.jellyfin_id}
          </Badge>
        </div>
        <div className="grid grid-cols-2 gap-4">
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
        </div>
        <div className="grid grid-rows-2 md:grid-rows-1 md:grid-cols-2 items-center gap-2">
          <GenreStatsGraph data={user.genre_stats} className="w-full" />
          <div></div>
        </div>
      </div>
      <HistoryTable
        server={server}
        data={user.watch_history.map((h) => ({ ...h, user: user }))}
      />
      <WatchTimePerDay data={user.watch_time_per_day} />
    </Container>
  );
}
