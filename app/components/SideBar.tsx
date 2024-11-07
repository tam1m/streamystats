"use client";

import { Server } from "@/lib/db";
import { UserMe } from "@/lib/me";
import {
  ActivitySquare,
  Bookmark,
  BookOpen,
  Calendar,
  Home,
  Layers,
  Library,
  Settings,
  TrendingUp,
  User,
  Users,
} from "lucide-react";
import { useParams } from "next/navigation";
import React, { useMemo } from "react";
import { ServerSelector } from "./ServerSelector";
import {
  Sidebar,
  SidebarContent,
  SidebarFooter,
  SidebarGroup,
  SidebarGroupContent,
  SidebarGroupLabel,
  SidebarMenu,
  SidebarMenuButton,
  SidebarMenuItem,
} from "./ui/sidebar";
import { UserMenu } from "./UserMenu";

const admin_items = [
  {
    title: "Users",
    url: "/users",
    icon: Users,
  },
  {
    title: "Settings",
    url: "/settings",
    icon: Settings,
  },
];

interface Props {
  servers: Server[];
  me?: UserMe;
  allowedToCreateServer?: boolean;
}

export const SideBar: React.FC<Props> = ({
  servers,
  me,
  allowedToCreateServer = false,
}) => {
  const params = useParams();

  const { id } = params as { id: string };

  const items = useMemo(() => {
    return [
      {
        title: "Dashboard",
        url: "/dashboard",
        icon: TrendingUp,
      },
      {
        title: "Library",
        url: "/library",
        icon: Library,
      },
      {
        title: "History",
        url: "/history",
        icon: Calendar,
      },
      {
        title: "Activity Log",
        url: "/activities",
        icon: ActivitySquare,
      },
      {
        title: "Me",
        url: "/users/" + me?.name,
        icon: User,
      },
    ];
  }, [me]);

  return (
    <Sidebar>
      <SidebarContent>
        <SidebarGroup>
          <ServerSelector
            servers={servers}
            allowedToCreateServer={allowedToCreateServer}
          />
        </SidebarGroup>
        <SidebarGroup>
          <SidebarGroupLabel>Home</SidebarGroupLabel>
          <SidebarGroupContent>
            <SidebarMenu>
              {items.map((item) => (
                <SidebarMenuItem key={item.title}>
                  <SidebarMenuButton asChild>
                    <a href={"/servers/" + id + item.url}>
                      <item.icon />
                      <span>{item.title}</span>
                    </a>
                  </SidebarMenuButton>
                </SidebarMenuItem>
              ))}
            </SidebarMenu>
          </SidebarGroupContent>
        </SidebarGroup>
        {allowedToCreateServer && (
          <SidebarGroup>
            <SidebarGroupLabel>Admin</SidebarGroupLabel>
            <SidebarGroupContent>
              <SidebarMenu>
                {admin_items.map((item) => (
                  <SidebarMenuItem key={item.title}>
                    <SidebarMenuButton asChild>
                      <a href={"/servers/" + id + item.url}>
                        <item.icon />
                        <span>{item.title}</span>
                      </a>
                    </SidebarMenuButton>
                  </SidebarMenuItem>
                ))}
              </SidebarMenu>
            </SidebarGroupContent>
          </SidebarGroup>
        )}
      </SidebarContent>
      <SidebarFooter>
        <UserMenu me={me} />
      </SidebarFooter>
    </Sidebar>
  );
};
