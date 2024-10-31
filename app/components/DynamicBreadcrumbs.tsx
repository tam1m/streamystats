"use client";

import { usePathname } from "next/navigation";
import {
  Breadcrumb,
  BreadcrumbItem,
  BreadcrumbLink,
  BreadcrumbList,
  BreadcrumbSeparator,
} from "./ui/breadcrumb";
import { House, Slash } from "lucide-react";
import React from "react";

export const DynamicBreadcrumbs: React.FC = () => {
  const pathname = usePathname();
  const pathSegments = pathname
    .split("/")
    .filter((segment) => segment)
    .slice(2); // Remove the first two segments (servers/<id>)
  return (
    <Breadcrumb>
      <BreadcrumbList>
        <BreadcrumbItem>
          <BreadcrumbLink href="/dashboard">
            <House className="h-4 w-4 ml-1" />
          </BreadcrumbLink>
        </BreadcrumbItem>
        {pathSegments.map((segment, index) => {
          const url = `/${pathSegments.slice(0, index + 1).join("/")}`;
          return (
            <React.Fragment key={url}>
              <BreadcrumbSeparator />
              <BreadcrumbItem>
                <BreadcrumbLink href={url}>
                  {segment.charAt(0).toUpperCase() + segment.slice(1)}
                </BreadcrumbLink>
              </BreadcrumbItem>
            </React.Fragment>
          );
        })}
      </BreadcrumbList>
    </Breadcrumb>
  );
};
