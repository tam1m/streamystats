import { redirect } from "next/navigation";
import { getServer, getServers } from "@/lib/db";
import { SignInForm } from "./SignInForm";

export default async function Setup({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const server = await getServer(id);

  if (!server) {
    redirect("/");
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
        <SignInForm server={server} />
      </div>
    </div>
  );
}
