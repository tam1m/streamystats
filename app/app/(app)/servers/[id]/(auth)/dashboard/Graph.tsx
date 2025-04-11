import { Server, getWatchTimeGraph } from "@/lib/db";
import { Suspense } from "react";
import { WatchTimeGraph } from "./WatchTimeGraph";

interface Props {
  server: Server;
  startDate: string;
  endDate: string;
}

export async function Graph({
  server,
  startDate,
  endDate,
}: Props): Promise<JSX.Element> {
  const graphData = await getWatchTimeGraph(server.id, startDate, endDate);

  if (!graphData) {
    return <p>No data available</p>;
  }

  return <WatchTimeGraph data={graphData} />;
}
export default Graph;
