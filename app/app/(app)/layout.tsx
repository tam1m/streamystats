import { getServers } from "@/lib/db";
import { redirect } from "next/navigation";
import { PropsWithChildren } from "react";

type Props = PropsWithChildren;

export default async function layout({ children }: Props) {
  return <>{children}</>;
}
