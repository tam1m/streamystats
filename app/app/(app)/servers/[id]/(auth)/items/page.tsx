import { Container } from "@/components/Container";
import { PageTitle } from "@/components/PageTitle";
import { getServer, getStatisticsItems, getStatisticsLibrary } from "@/lib/db";
import { redirect } from "next/navigation";
import { ItemWatchStatsTable } from "./ItemWatchStatsTable";
import { LibraryStatisticsCards } from "./LibraryStatisticsCards";

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

  console.log(libraryStats);

  return (
    <Container>
      <PageTitle
        title="Items"
        subtitle="Search for any movie or episode on your server."
      />
      <LibraryStatisticsCards data={libraryStats} />
      <ItemWatchStatsTable server={server} />
    </Container>
  );
}
