import { Statistics, MostWatchedItem, Server } from "@/lib/db";
import { formatDuration } from "@/lib/utils";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { MoreHorizontal } from "lucide-react";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { Button } from "@/components/ui/button";

interface Props {
  data: Statistics["most_watched_items"];
  server: Server;
}

export const MostPopularItems: React.FC<Props> = ({ data, server }) => {
  const renderItems = (items: MostWatchedItem[], type: "Movie" | "Episode") => (
    <div>
      <h2 className="text-xl font-bold mb-4">Most Watched {type}s</h2>
      <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
        {items.slice(0, 3).map((item) => (
          <Card key={item.id}>
            <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2 relative">
              <CardTitle>
                {item.name}
                {item.type === "Episode" && (
                  <div>
                    <p className="text-sm">{item.series_name}</p>
                    <p className="text-sm text-neutral-500">
                      {`${item.season_name} - Episode ${item.index_number}`}
                    </p>
                  </div>
                )}
                {item.type === "Movie" && (
                  <div>
                    <p className="text-sm text-neutral-500">
                      {item.production_year}
                    </p>
                  </div>
                )}
              </CardTitle>
              <DropdownMenu>
                <DropdownMenuTrigger asChild>
                  <Button
                    variant="ghost"
                    className="h-8 w-8 p-0 absolute top-4 right-4"
                  >
                    <span className="sr-only">Open menu</span>
                    <MoreHorizontal className="h-4 w-4" />
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
            <CardContent>
              <p className="text-sm font-semibold mt-2">
                Watch time: {formatDuration(item.total_play_duration)}
              </p>
              <p className="text-neutral-500 text-sm">
                Played {item.total_play_count} times
              </p>
            </CardContent>
          </Card>
        ))}
      </div>
    </div>
  );

  return (
    <div className="flex flex-col gap-4">
      {renderItems(data.Movie, "Movie")}
      {renderItems(data.Episode, "Episode")}
    </div>
  );
};
