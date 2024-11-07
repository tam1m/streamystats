import { Container } from "@/components/Container";
import { PageTitle } from "@/components/PageTitle";
import { getActivities, getServer } from "@/lib/db";
import { redirect } from "next/navigation";
import { ActivityLogTable } from "./ActivityLogTable";

export default async function ActivitiesPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const server = await getServer(id);

  if (!server) {
    redirect("/setup");
  }

  return (
    <Container>
      <PageTitle title="Activity Log" subtitle="All events on your server." />
      <ActivityLogTable server={server} />
    </Container>
  );
}
