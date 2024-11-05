"use client";

import React from "react";
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
import { useParams } from "next/navigation";
import {
  Calendar,
  Home,
  Layers,
  PlusIcon,
  Settings,
  Users,
} from "lucide-react";
import { ServerSelector } from "./ServerSelector";
import { Server } from "@/lib/db";
import { UserMenu } from "./UserMenu";
import { UserMe } from "@/lib/me";

const items = [
  {
    title: "Dashboard",
    url: "/dashboard",
    icon: Home,
  },
  {
    title: "History",
    url: "/history",
    icon: Calendar,
  },
  {
    title: "Items",
    url: "/items",
    icon: Layers,
  },
];

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
