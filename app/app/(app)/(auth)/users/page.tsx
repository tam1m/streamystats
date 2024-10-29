import { Container } from "@/components/Container";
import { getServer, getUsers } from "@/lib/db";
import { formatDuration } from "@/lib/utils";
import Link from "next/link";
import { UserTable } from "./UserTable";
import { PageTitle } from "@/components/PageTitle";

export default async function UsersPage() {
  const server = await getServer();
  if (!server) {
    return <div>Server not found</div>;
  }

  const users = await getUsers(server.id);

  console.log(users);
  return (
    <Container>
      <PageTitle title="Users" />
      <UserTable data={users} />
    </Container>
  );
}
