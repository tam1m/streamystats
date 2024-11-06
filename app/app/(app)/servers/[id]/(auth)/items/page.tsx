import { Container } from "@/components/Container";
import { PageTitle } from "@/components/PageTitle";
import { getServer, getStatisticsItems } from "@/lib/db";
import { redirect } from "next/navigation";
import { ItemWatchStatsTable } from "./ItemWatchStatsTable";

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

  return (
    <Container>
      <PageTitle
        title="Items"
        subtitle="Search for any movie or episode on your server."
      />
      <ItemWatchStatsTable server={server} />
    </Container>
  );
}
