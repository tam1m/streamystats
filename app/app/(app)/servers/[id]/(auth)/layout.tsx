"use server";

import { DynamicBreadcrumbs } from "@/components/DynamicBreadcrumbs";
import { FadeInWrapper } from "@/components/FadeInWrapper";
import { SideBar } from "@/components/SideBar";
import { SuspenseLoading } from "@/components/SuspenseLoading";
import { Separator } from "@/components/ui/separator";
import { SidebarProvider, SidebarTrigger } from "@/components/ui/sidebar";
import { UserMenu } from "@/components/UserMenu";
import { getMe, getServers } from "@/lib/db";
import { PropsWithChildren, Suspense } from "react";

interface Props extends PropsWithChildren {}

export default async function layout({ children }: Props) {
  const servers = await getServers();
  const me = await getMe();

  return (
    <SidebarProvider>
      <>
        <SideBar servers={servers} me={me} />
        <Suspense fallback={<SuspenseLoading />}>
          <main className="flex flex-col w-full">
            <div className="flex flex-row items-center p-4 gap-2">
              <SidebarTrigger />
              <Separator orientation="vertical" />
              <DynamicBreadcrumbs />
            </div>
            <FadeInWrapper>{children}</FadeInWrapper>
          </main>
        </Suspense>
      </>
    </SidebarProvider>
  );
}
