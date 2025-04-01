import { Container } from "@/components/Container";
import { PageTitle } from "@/components/PageTitle";
import {
  getServer,
  getStatisticsItems,
  getStatisticsLibrary,
  getUnwatchedItems,
} from "@/lib/db";
import { redirect } from "next/navigation";
import { ItemWatchStatsTable } from "./ItemWatchStatsTable";
import { LibraryStatisticsCards } from "./LibraryStatisticsCards";
import { UnwatchedTable } from "@/components/UnwatchedTable";

export default async function DashboardPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const server = await getServer(id);

  if (!server) {
    redirect("/not-found");
  }

  const libraryStats = await getStatisticsLibrary(server.id);
  const unwatchedItems = await getUnwatchedItems(server.id);

  return (
    <Container>
      <PageTitle
        title="Library"
        subtitle="Search for any movie or episode on your server."
      />
      <LibraryStatisticsCards data={libraryStats} />
      <ItemWatchStatsTable server={server} />
      {/* <UnwatchedTable server={server} data={unwatchedItems} /> */}
    </Container>
  );
}
