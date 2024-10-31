"use server";

import { DynamicBreadcrumbs } from "@/components/DynamicBreadcrumbs";
import { FadeInWrapper } from "@/components/FadeInWrapper";
import { SideBar } from "@/components/SideBar";
import { SuspenseLoading } from "@/components/SuspenseLoading";
import { Separator } from "@/components/ui/separator";
import { SidebarProvider, SidebarTrigger } from "@/components/ui/sidebar";
import { UserMenu } from "@/components/UserMenu";
import { getMe, getServer, getServers, getUser } from "@/lib/db";
import { PropsWithChildren, Suspense } from "react";

interface Props extends PropsWithChildren {
  params: Promise<{ id: string }>;
}

export default async function layout({ children, params }: Props) {
  const { id } = await params;

  const servers = await getServers();
  const server = await getServer(id);

  const me = await getMe();
  const user = await getUser(me?.name, server?.id);

  return (
    <SidebarProvider>
      <>
        <SideBar
          servers={servers}
          me={me}
          allowedToCreateServer={user?.is_administrator}
        />
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
