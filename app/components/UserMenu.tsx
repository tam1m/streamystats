"use client";

import { getMe, logout } from "@/lib/db";
import { ChevronsUpDown, Loader2, LogOut } from "lucide-react";
import { useParams, useRouter } from "next/navigation";
import { useMemo, useState } from "react";
import { Avatar, AvatarFallback } from "./ui/avatar";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "./ui/dropdown-menu";
import { SidebarMenuButton } from "./ui/sidebar";
import { cookies } from "next/headers";

interface Props {
  me?: { name: string };
}

export const UserMenu: React.FC<Props> = ({ me }) => {
  const router = useRouter();
  const params = useParams();
  const [loading, setLoading] = useState(false);

  const { id } = params as { id: string };

  if (!me) return null;

  const shortName = useMemo(() => {
    if (me.name.length >= 2) {
      return me.name.slice(0, 2).toUpperCase();
    } else {
      return me.name.toUpperCase();
    }
  }, [me.name]);

  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <SidebarMenuButton
          size="lg"
          className="data-[state=open]:bg-sidebar-accent data-[state=open]:text-sidebar-accent-foreground"
        >
          <Avatar className="h-8 w-8 rounded-lg">
            <AvatarFallback className="rounded-lg">{shortName}</AvatarFallback>
          </Avatar>
          <div className="grid flex-1 text-left text-sm leading-tight">
            <span className="truncate font-semibold">{me.name}</span>
          </div>
          <ChevronsUpDown className="ml-auto size-4" />
        </SidebarMenuButton>
      </DropdownMenuTrigger>
      <DropdownMenuContent
        className="w-[--radix-dropdown-menu-trigger-width] min-w-56 rounded-lg"
        side="bottom"
        align="end"
        sideOffset={4}
      >
        <DropdownMenuLabel className="p-0 font-normal">
          <div className="flex items-center gap-2 px-1 py-1.5 text-left text-sm">
            <Avatar className="h-8 w-8 rounded-lg">
              <AvatarFallback className="rounded-lg">
                {shortName}
              </AvatarFallback>
            </Avatar>
            <div className="grid flex-1 text-left text-sm leading-tight">
              <span className="truncate font-semibold">{me.name}</span>
            </div>
          </div>
        </DropdownMenuLabel>
        <DropdownMenuSeparator />
        {/* <DropdownMenuGroup>
          <DropdownMenuItem>
            <Bell />
            Notifications
          </DropdownMenuItem>
        </DropdownMenuGroup> */}
        {/* <DropdownMenuSeparator /> */}
        <DropdownMenuItem
          onClick={async () => {
            setLoading(true);
            // Handle logout by removing cookie from server
            // Redirect to login page
            await logout();
            router.push(`/servers/${id}/login`);
            setLoading(false);
          }}
        >
          <LogOut />
          {loading ? <Loader2 className="h-8 w-8 animate-spin" /> : "Log out"}
        </DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>
  );
};
