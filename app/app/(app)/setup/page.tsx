import { redirect } from "next/navigation";
import { SetupForm } from "./SetupForm";
import { getServers } from "@/lib/db";

export default async function Setup() {
  const servers = await getServers();

  if (servers?.[0]?.api_key) {
    redirect("/dashboard");
  }

  return (
    <div className="grid place-items-center h-screen w-screen">
      <SetupForm />
    </div>
  );
}
