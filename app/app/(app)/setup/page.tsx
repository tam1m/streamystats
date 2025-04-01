import { redirect } from "next/navigation";
import { getServers, getUser } from "@/lib/db";
import { SetupForm } from "./SetupForm";
import { getMe } from "@/lib/me";
import { Spinner } from "@/components/Spinner";

export default async function Setup() {
  const servers = await getServers();

  if (servers.length > 0) {
    const s = servers[0];

    if (s && s.id) {
      const me = await getMe();

      if (me && me.name) {
        const user = await getUser(me.name, s.id);

        if (user && !user.is_administrator) {
          redirect(`/`);
        }
      } else {
        console.warn(
          "User is not logged in or user information is missing, redirecting to login..."
        );
        redirect(`/servers/${s.id}/login`);
      }
    } else {
      console.error("Server information is missing or incomplete");
    }
  }

  return <SetupForm />;
}
