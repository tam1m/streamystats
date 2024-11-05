import { Container } from "@/components/Container";
import { PageTitle } from "@/components/PageTitle";
import { getServer, getStatisticsItems } from "@/lib/db";
import { redirect } from "next/navigation";

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

  const items = await getStatisticsItems(server?.id);

  return (
    <Container>
      <PageTitle title="Items" />
      <p className="text-neutral-500">Coming soon...</p>
    </Container>
  );
}
