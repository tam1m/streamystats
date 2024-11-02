import { redirect } from "next/navigation";
import { getServers, getUser } from "@/lib/db";
import { SetupForm } from "./SetupForm";
import { getMe } from "@/lib/me";

export default async function Setup() {
  const servers = await getServers();
  const server = servers?.[0];

  const me = await getMe();
  const user = await getUser(me?.name, server?.id);

  if (server && !user?.is_administrator) {
    redirect(`/`);
  }

  return (
    <div className="grid md:grid-cols-2 h-screen w-screen">
      <div className="bg-neutral-900 hidden md:grid place-items-center px-8">
        <div>
          <p className="font-bold text-3xl bg-clip-text text-transparent bg-gradient-to-r from-blue-500 via-teal-500 to-purple-500">
            Streamystats
          </p>
          <p>
            Track your Jellyfin stats and view them in a beautiful dashboard.
          </p>
        </div>
      </div>
      <div className="grid place-items-center py-12 md:py-0">
        <SetupForm />
      </div>
    </div>
  );
}
