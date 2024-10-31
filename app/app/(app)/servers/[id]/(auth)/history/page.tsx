import { Container } from "@/components/Container";
import { getServers, getStatisticsHistory } from "@/lib/db";
import { HistoryTable } from "./HistoryTable";
import { PageTitle } from "@/components/PageTitle";
import { redirect } from "next/navigation";

export default async function HistoryPage() {
  const servers = await getServers();
  const server = servers?.[0];

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
