import { Container } from "@/components/Container";
import { getServer, getUsers } from "@/lib/db";
import { formatDuration } from "@/lib/utils";
import Link from "next/link";
import { UserTable } from "./UserTable";
import { PageTitle } from "@/components/PageTitle";
import { redirect } from "next/navigation";

export default async function UsersPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const server = await getServer(id);

  if (!server) {
    redirect("/");
  }

  const users = await getUsers(server.id);

  console.log(users);
  return (
    <Container>
      <PageTitle title="Users" />
      <UserTable data={users} server={server} />
    </Container>
  );
}
