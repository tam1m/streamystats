import { Container } from "@/components/Container";
import { PageTitle } from "@/components/PageTitle";
import { Badge } from "@/components/ui/badge";
import { getServer, getUser } from "@/lib/db";
import { HistoryTable } from "../../history/HistoryTable";
import { formatDuration } from "@/lib/utils";

export default async function User({ params }: { params: { name: string } }) {
  console.log("name", params.name);
  const server = await getServer();

  if (!server) {
    return (
      <div>
        <p>Server not found</p>
      </div>
    );
  }

  const user = await getUser(params.name, server.id);

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
      </div>
      <HistoryTable
        server={server}
        data={user.watch_history.map((h) => ({ ...h, user: user }))}
      />
    </Container>
  );
}
