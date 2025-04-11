import { Server, getStatistics } from "@/lib/db";
import MostWatchedDate from "./MostWatchedDate";
import { MostWatchedItems } from "./MostWatchedItems";
import TotalWatchTime from "./TotalWatchTime";
import { WatchTimePerWeekDay } from "./WatchTimePerWeekDay";

export async function StatsWithSuspense({
  server,
  startDate,
  endDate,
}: {
  server: Server;
  startDate: string;
  endDate: string;
}) {
  const data = await getStatistics(server.id, startDate, endDate);
  if (!data) {
    return <p>No data available</p>;
  }
  return (
    <div className="flex flex-col gap-6">
      <div className="flex md:flex-row flex-col gap-2">
        <TotalWatchTime data={data.total_watch_time} />
        <MostWatchedDate data={data.most_watched_date} />
      </div>
      <MostWatchedItems data={data.most_watched_items} server={server} />
      <WatchTimePerWeekDay data={data.average_watchtime_per_week_day} />
    </div>
  );
}
export default StatsWithSuspense;
