"use client";

import { Server } from "@/lib/db";
import { Button } from "./ui/button";
import { useRouter } from "next/navigation";
import Link from "next/link";

interface Props {
  server: Server;
}

export const NavBar: React.FC<Props> = ({ server }) => {
  const router = useRouter();

  if (!server?.name) return null;

  return (
    <div className="bg-neutral-900 flex flex-row items-center w-full p-4">
      <Link href={"/dashboard"}>
        <p className="font-bold">{server.name}</p>
      </Link>
      <Button
        className="ml-auto"
        onClick={() => {
          router.push("/settings");
        }}
      >
        Settings
      </Button>
    </div>
  );
};
