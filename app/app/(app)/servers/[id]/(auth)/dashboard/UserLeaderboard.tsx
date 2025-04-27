import { Server, getUsers } from "@/lib/db";
import { UserLeaderboardTable } from "./UserLeaderBoardTable";

interface Props {
  server: Server;
}

export const UserLeaderboard = async ({ server }: Props) => {
  const users = await getUsers(server.id);

  return <UserLeaderboardTable users={users} server={server} />;
};
