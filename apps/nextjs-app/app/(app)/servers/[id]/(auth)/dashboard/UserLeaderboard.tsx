import { getTotalWatchTimeForUsers, getUsers } from "@/lib/db/users";
import { UserLeaderboardTable } from "./UserLeaderBoardTable";
import { Server, User } from "@streamystats/database/schema";

interface Props {
  server: Server;
}

export const UserLeaderboard = async ({ server }: Props) => {
  const users = await getUsers(server.id);
  const totalWatchTime = await getTotalWatchTimeForUsers(
    users.map((user: User) => user.id)
  );

  return (
    <UserLeaderboardTable
      users={users}
      server={server}
      totalWatchTime={totalWatchTime}
    />
  );
};
