import { redirect } from "next/navigation";
import { getServers, getUser } from "@/lib/db";
import { SetupForm } from "./SetupForm";
import { getMe } from "@/lib/me";

export default async function Setup() {
  console.log("(app)/setup/page.tsx ~ Setup");

  const servers = await getServers();

  console.log("(app)/setup/page.tsx ~ nr of servers", servers.length);

  if (servers.length > 0) {
    const s = servers[0];

    if (s && s.id) {
      console.log("(app)/setup/page.tsx ~ found a server", s);

      const me = await getMe();
      console.log("(app)/setup/page.tsx ~ me", me);

      if (me && me.name) {
        const user = await getUser(me.name, s.id);

        if (user && !user.is_administrator) {
          redirect(`/`);
        }
      } else {
        console.error("User information is missing or incomplete");
      }
    } else {
      console.error("Server information is missing or incomplete");
    }
  }

  return <SetupForm />;
}
