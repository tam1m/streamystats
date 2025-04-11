"use client";

import { Badge } from "@/components/ui/badge";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Progress } from "@/components/ui/progress";
import {
  Tooltip,
  TooltipContent,
  TooltipProvider,
  TooltipTrigger,
} from "@/components/ui/tooltip";
import { ActiveSession, Server } from "@/lib/db";
import { useQuery } from "@tanstack/react-query";
import { formatDistanceToNow } from "date-fns";
import { Clock, Film, MonitorPlay, Pause, Play, Tv, User } from "lucide-react";
import LoadingSessions from "./LoadingSessions";
import { Poster } from "./Poster";

export function ActiveSessions({ server }: { server: Server }) {
  const { data, isPending } = useQuery({
    queryKey: ["activeSessions", server.id],
    queryFn: async () =>
      (await fetch(`/api/Sessions?serverId=${server.id}`).then((res) =>
        res.json(),
      )) as ActiveSession[],
    refetchInterval: 500,
  });

  const sortedSessions =
    data?.sort((a, b) => {
      return b.position_ticks - a.position_ticks;
    }) || [];

  if (isPending) {
    return <LoadingSessions />;
  }

  if (!data || data?.length === 0) {
    return (
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <MonitorPlay className="h-5 w-5" />
            <span>Active Sessions</span>
          </CardTitle>
          <CardDescription>
            Currently playing content on your server
          </CardDescription>
        </CardHeader>
        <CardContent>
          <p className="text-muted-foreground">
            No active sessions at the moment
          </p>
        </CardContent>
      </Card>
    );
  }

  return (
    <Card className="border-0 p-0 m-0">
      <CardHeader className="px-0 pt-0">
        <CardTitle className="flex items-center gap-2">
          <MonitorPlay className="h-5 w-5" />
          <span>Active Sessions</span>
          <Badge variant="outline" className="ml-2">
            {data.length}
          </Badge>
        </CardTitle>
        <CardDescription>
          Currently playing content on your server
        </CardDescription>
      </CardHeader>
      <CardContent className="px-0 pb-0">
        <div className="space-y-4">
          {sortedSessions.map((session) => (
            <div
              key={session.session_key}
              className="flex flex-col md:flex-row md:items-center border rounded-lg p-4  items-start"
            >
              <div className="w-32 mb-2 md:mb-0 md:mr-4">
                <Poster item={session.item} server={server} />
              </div>
              <div className="flex flex-col space-y-3 flex-1">
                <div className="flex flex-col md:flex-row md:items-center justify-between gap-2 md:gap-0">
                  <div className="flex items-center gap-2">
                    {session.is_paused ? (
                      <Pause className="h-4 w-4 text-amber-500" />
                    ) : (
                      <Play className="h-4 w-4 text-green-500" />
                    )}
                    <h3 className="font-semibold">{session.item?.name}</h3>
                    <MediaTypeBadge type={session.item?.type} />
                  </div>
                  <div className="flex items-center gap-2">
                    <TooltipProvider>
                      <Tooltip>
                        <TooltipTrigger asChild>
                          <div className="flex items-center gap-1 text-xs text-muted-foreground">
                            <Clock className="h-3 w-3" />
                            {session.formatted_position} /{" "}
                            {session.formatted_runtime}
                          </div>
                        </TooltipTrigger>
                        <TooltipContent>
                          <p>Current position / Total runtime</p>
                        </TooltipContent>
                      </Tooltip>
                    </TooltipProvider>
                  </div>
                </div>

                {session.item?.type === "Episode" &&
                  session.item.series_name && (
                    <div className="text-sm text-muted-foreground">
                      {session.item.series_name}
                      {session.item.parent_index_number &&
                        session.item.index_number && (
                          <span>
                            {" "}
                            - S{session.item.parent_index_number}:E
                            {session.item.index_number}
                          </span>
                        )}
                    </div>
                  )}

                <div className="flex flex-col gap-1">
                  <div className="flex items-center gap-2 mb-1">
                    <User className="h-3 w-3 text-muted-foreground" />
                    <span className="text-sm">
                      {session.user?.name || "Unknown User"}
                    </span>
                    <span className="text-xs text-muted-foreground">•</span>
                    <span className="text-xs text-muted-foreground">
                      {session.client} on {session.device_name}
                    </span>
                  </div>

                  <div className="flex items-center gap-2">
                    <Progress
                      value={session.progress_percent}
                      className="h-2"
                    />
                    <span className="text-xs font-medium">
                      {Math.round(session.progress_percent)}%
                    </span>
                  </div>
                </div>

                {session.last_activity_date && (
                  <div className="text-xs text-muted-foreground">
                    Last activity:{" "}
                    {formatDistanceToNow(new Date(session.last_activity_date), {
                      addSuffix: true,
                    })}
                  </div>
                )}
              </div>
            </div>
          ))}
        </div>
      </CardContent>
    </Card>
  );
}

function MediaTypeBadge({ type }: { type: string | undefined | null }) {
  if (!type) return null;

  let variant: "default" | "secondary" | "outline" = "outline";
  let icon = null;

  switch (type) {
    case "Movie":
      variant = "secondary";
      icon = <Film className="h-3 w-3 mr-1" />;
      break;
    case "Episode":
      variant = "outline";
      icon = <Tv className="h-3 w-3 mr-1" />;
      break;
  }

  return (
    <Badge variant={variant} className="ml-2 text-xs">
      <div className="flex items-center">
        {icon}
        {type}
      </div>
    </Badge>
  );
}
