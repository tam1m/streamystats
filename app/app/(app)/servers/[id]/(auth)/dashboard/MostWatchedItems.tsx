"use client";

import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { MostWatchedItem, Server, Statistics } from "@/lib/db";
import { formatDuration } from "@/lib/utils";
import { MoreHorizontal } from "lucide-react";
import { Poster } from "./Poster";

interface Props {
  data: Statistics["most_watched_items"];
  server: Server;
}

export const MostWatchedItems: React.FC<Props> = ({ data, server }) => {
  const renderItems = (
    items: MostWatchedItem[],
    type: "Movie" | "Episode" | "Series",
    title: string
  ) => (
    <div>
      <h2 className="text-xl font-bold mb-4">Most Watched {title}</h2>
      {items.length === 0 && (
        <p className="text-neutral-500">
          No {type.toLowerCase()}s watched yet.
        </p>
      )}
      <div className="flex flex-col gap-2">
        {items?.slice(0, 5).map((item, index) => (
          <Card
            key={`${type}-${item.jellyfin_id || item.id || index}`}
            className="flex flex-row items-center px-2 py-2 min-h-[120px]"
          >
            <div className="rounded-lg overflow-hidden w-16">
              <Poster
                item={item}
                server={server}
                preferredImageType="Primary"
              />
            </div>
            <div className="flex-1 overflow-hidden">
              <CardHeader className="flex flex-row items-center justify-between space-y-0 py-1 px-2 relative">
                <CardTitle className="text-sm">
                  {item.type === "Episode" && (
                    <div className="flex gap-0.5 flex-col">
                      <p className="text-xs text-neutral-500 font-normal truncate">
                        {item.series_name}
                        {" - "}
                        <span className="text-xs text-neutral-500 font-normal truncate">
                          {`${item.season_name} - E${item.index_number}`}
                        </span>
                      </p>
                      <p className="truncate">{item.name}</p>
                    </div>
                  )}
                  {item.type === "Movie" && (
                    <div className="flex flex-col gap-0.5">
                      <p className="truncate">{item.name}</p>
                      <p className="text-xs text-neutral-500 font-normal">
                        {item.production_year}
                      </p>
                    </div>
                  )}
                  {item.type === "Series" && (
                    <div className="flex flex-col gap-0.5">
                      <p className="truncate">{item.name}</p>
                      <p className="text-xs text-neutral-500 font-normal">
                        {item.production_year}
                      </p>
                    </div>
                  )}
                </CardTitle>
                <DropdownMenu>
                  <DropdownMenuTrigger asChild>
                    <Button
                      variant="ghost"
                      className="h-6 w-6 p-0 absolute top-0 right-0"
                    >
                      <span className="sr-only">Open menu</span>
                      <MoreHorizontal className="h-3 w-3" />
                    </Button>
                  </DropdownMenuTrigger>
                  <DropdownMenuContent align="end">
                    <DropdownMenuItem>
                      <a
                        href={`${server.url}/web/#/details?id=${item.jellyfin_id}`}
                        target="_blank"
                        rel="noopener noreferrer"
                      >
                        Open in Jellyfin
                      </a>
                    </DropdownMenuItem>
                  </DropdownMenuContent>
                </DropdownMenu>
              </CardHeader>
              <CardContent className="pt-0 pb-2 px-2">
                <p className="text-xs font-semibold">
                  {formatDuration(item.total_play_duration || 0)}
                </p>
                <p className="text-neutral-500 text-xs">
                  Played {item.total_play_count} times
                </p>
              </CardContent>
            </div>
          </Card>
        ))}
      </div>
    </div>
  );

  return (
    <div className="grid md:grid-cols-2 xl:grid-cols-3 gap-4">
      {renderItems(data?.Movie || [], "Movie", "Movies")}
      {renderItems(data?.Series || [], "Series", "Series")}
      {renderItems(data?.Episode || [], "Episode", "Episodes")}
    </div>
  );
};
