"use client";

import { Server } from "@/lib/db";
import {
  Check,
  ChevronsUpDown,
  GalleryVerticalEnd,
  PlusIcon,
} from "lucide-react";
import { useParams, useRouter } from "next/navigation";
import { useMemo } from "react";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "./ui/dropdown-menu";
import { SidebarMenuButton } from "./ui/sidebar";

interface Props {
  servers: Server[];
  allowedToCreateServer?: boolean;
}

export const ServerSelector: React.FC<Props> = ({
  servers,
  allowedToCreateServer = false,
}) => {
  const params = useParams();
  const { id } = params as { id: string };

  const currentServer = useMemo(() => {
    return servers.find((server) => server.id === Number(id));
  }, [servers, id]);

  const router = useRouter();

  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <SidebarMenuButton
          size="lg"
          className="data-[state=open]:bg-sidebar-accent data-[state=open]:text-sidebar-accent-foreground"
        >
          <div className="flex aspect-square size-8 items-center justify-center rounded-lg bg-sidebar-primary text-sidebar-primary-foreground">
            <GalleryVerticalEnd className="size-4" />
          </div>
          <div className="flex flex-col gap-0.5 leading-none">
            <span className="font-semibold">Server</span>
            <span className="">{currentServer?.name || "N/A"}</span>
          </div>
          <ChevronsUpDown className="ml-auto" />
        </SidebarMenuButton>
      </DropdownMenuTrigger>
      <DropdownMenuContent
        className="w-[--radix-dropdown-menu-trigger-width]"
        align="start"
      >
        {servers.map((server) => (
          <DropdownMenuItem
            key={server.id}
            onSelect={() => {
              router.push(`/servers/${server.id}/login`);
            }}
          >
            {server.name} {server === server && <Check className="ml-auto" />}
          </DropdownMenuItem>
        ))}
        {allowedToCreateServer && (
          <DropdownMenuItem>
            <a href={"/setup/"} className="flex flex-row items-center gap-2">
              <PlusIcon />
              <span>Add server</span>
            </a>
          </DropdownMenuItem>
        )}
      </DropdownMenuContent>
    </DropdownMenu>
  );
};
