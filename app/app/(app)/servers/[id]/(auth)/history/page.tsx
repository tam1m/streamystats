import { Container } from "@/components/Container";
import { PageTitle } from "@/components/PageTitle";
import { getServer, getStatisticsHistory } from "@/lib/db";
import { redirect } from "next/navigation";
import { HistoryTable } from "./HistoryTable";

export default async function HistoryPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const server = await getServer(id);

  if (!server) {
    redirect("/setup");
  }

  const data = await getStatisticsHistory(server.id);

  return (
    <Container>
      <PageTitle title="History" />
      <HistoryTable data={data} server={server} />
    </Container>
  );
}
