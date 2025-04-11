"use client";

import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { Switch } from "@/components/ui/switch";
import { MostWatchedItem, Server, Statistics } from "@/lib/db";
import { formatDuration } from "@/lib/utils";
import { MoreHorizontal, Settings } from "lucide-react";
import { useEffect, useState } from "react";
import { Poster } from "./Poster";

interface Props {
  data: Statistics["most_watched_items"];
  server: Server;
}

// Local storage key
const STORAGE_KEY = "mostWatchedColumnsVisibility";

// Default column visibility state
const DEFAULT_VISIBILITY = {
  movies: true,
  series: true,
  episodes: true,
};

export const MostWatchedItems: React.FC<Props> = ({ data, server }) => {
  const [visibleColumns, setVisibleColumns] = useState(DEFAULT_VISIBILITY);
  const [initialized, setInitialized] = useState(false);

  // Load saved preferences from localStorage on mount
  useEffect(() => {
    try {
      const savedPreferences = localStorage.getItem(STORAGE_KEY);
      if (savedPreferences) {
        setVisibleColumns(JSON.parse(savedPreferences));
      }
    } catch (error) {
      console.error("Failed to load column visibility preferences:", error);
    }
    setInitialized(true);
  }, []);

  // Save preferences to localStorage whenever they change
  useEffect(() => {
    if (initialized) {
      try {
        localStorage.setItem(STORAGE_KEY, JSON.stringify(visibleColumns));
      } catch (error) {
        console.error("Failed to save column visibility preferences:", error);
      }
    }
  }, [visibleColumns, initialized]);

  const toggleColumn = (column: "movies" | "series" | "episodes") => {
    setVisibleColumns((prev) => ({
      ...prev,
      [column]: !prev[column],
    }));
  };

  // Calculate number of visible columns for grid
  const visibleColumnCount =
    Object.values(visibleColumns).filter(Boolean).length;
  const gridColsClass =
    visibleColumnCount === 1
      ? "md:grid-cols-1"
      : visibleColumnCount === 2
        ? "md:grid-cols-2"
        : "md:grid-cols-3";

  const renderItems = (
    items: MostWatchedItem[],
    type: "Movie" | "Episode" | "Series",
    title: string,
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
    <div className="space-y-4">
      <div className={`grid ${gridColsClass} gap-4`}>
        {visibleColumns.movies &&
          renderItems(data?.Movie || [], "Movie", "Movies")}
        {visibleColumns.series &&
          renderItems(data?.Series || [], "Series", "Series")}
        {visibleColumns.episodes &&
          renderItems(data?.Episode || [], "Episode", "Episodes")}
      </div>
      <div className="flex justify-end">
        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <Button variant="outline" size="sm" className="ml-auto">
              <Settings className="h-4 w-4 mr-2" /> Display Options
            </Button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end" className="w-56">
            <DropdownMenuLabel>Visible Sections</DropdownMenuLabel>
            <DropdownMenuSeparator />
            <div className="p-2">
              <div className="flex items-center justify-between mb-2">
                <span className="text-sm">Movies</span>
                <Switch
                  checked={visibleColumns.movies}
                  onCheckedChange={() => toggleColumn("movies")}
                />
              </div>
              <div className="flex items-center justify-between mb-2">
                <span className="text-sm">Series</span>
                <Switch
                  checked={visibleColumns.series}
                  onCheckedChange={() => toggleColumn("series")}
                />
              </div>
              <div className="flex items-center justify-between">
                <span className="text-sm">Episodes</span>
                <Switch
                  checked={visibleColumns.episodes}
                  onCheckedChange={() => toggleColumn("episodes")}
                />
              </div>
            </div>
            <DropdownMenuSeparator />
            <DropdownMenuItem
              onClick={() => setVisibleColumns(DEFAULT_VISIBILITY)}
              className="justify-center text-xs text-muted-foreground"
            >
              Reset to default
            </DropdownMenuItem>
          </DropdownMenuContent>
        </DropdownMenu>
      </div>
    </div>
  );
};
