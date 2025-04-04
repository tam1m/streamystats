import { getActiveSessions, Server } from "@/lib/db";
import { ActiveSessions } from "./ActiveSessions";

export async function ActiveSessionsWithSuspense({
  server,
}: {
  server: Server;
}) {
  const sessions = await getActiveSessions(server.id);
  return <ActiveSessions server={server} sessions={sessions} />;
}
