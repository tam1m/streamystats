"use client";

import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { formatDuration } from "@/lib/utils";
import { Item } from "@streamystats/database/schema";
import {
  TrendingUp,
  Users,
  Calendar,
  Percent,
  Clock,
  Video,
  Folder,
  Tag,
  Play,
  CheckCircle,
} from "lucide-react";

interface SeriesEpisodeStats {
  total_seasons: number;
  total_episodes: number;
  watched_episodes: number;
  watched_seasons: number;
}

interface ItemDetailsResponse {
  item: Item;
  total_views: number;
  total_watch_time: number;
  completion_rate: number;
  first_watched: Date | null;
  last_watched: Date | null;
  users_watched: any[];
  watch_history: any[];
  watch_count_by_month: any[];
  episode_stats?: SeriesEpisodeStats;
}

interface ItemMetadataProps {
  item: Item;
  statistics: ItemDetailsResponse;
}

function formatDate(date: Date | null): string {
  if (!date) return "Never";
  return new Intl.DateTimeFormat("en-US", {
    year: "numeric",
    month: "short",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  }).format(new Date(date));
}

export function ItemMetadata({ item, statistics }: ItemMetadataProps) {
  const {
    total_views,
    total_watch_time,
    completion_rate,
    first_watched,
    last_watched,
    users_watched,
  } = statistics;

  return (
    <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
      {/* Watch Statistics */}
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <TrendingUp className="w-5 h-5" />
            Watch Statistics
          </CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="grid grid-cols-2 gap-4">
            <div className="flex flex-col">
              <span className="text-2xl font-bold text-primary">
                {total_views}
              </span>
              <span className="text-sm text-muted-foreground">Total Views</span>
            </div>
            <div className="flex flex-col">
              <span className="text-2xl font-bold text-primary">
                {formatDuration(total_watch_time)}
              </span>
              <span className="text-sm text-muted-foreground">
                Total Watch Time
              </span>
            </div>
          </div>

          <div className="grid grid-cols-2 gap-4">
            <div className="flex flex-col">
              <div className="flex items-center gap-1">
                <Percent className="w-4 h-4" />
                <span className="text-lg font-semibold">
                  {completion_rate.toFixed(1)}%
                </span>
              </div>
              <span className="text-sm text-muted-foreground">
                Avg Completion
              </span>
            </div>
            <div className="flex flex-col">
              <div className="flex items-center gap-1">
                <Users className="w-4 h-4" />
                <span className="text-lg font-semibold">
                  {users_watched.length}
                </span>
              </div>
              <span className="text-sm text-muted-foreground">
                Unique Viewers
              </span>
            </div>
          </div>

          <div className="space-y-2">
            <div className="flex items-center justify-between">
              <span className="text-sm text-muted-foreground">
                First Watched:
              </span>
              <span className="text-sm">{formatDate(first_watched)}</span>
            </div>
            <div className="flex items-center justify-between">
              <span className="text-sm text-muted-foreground">
                Last Watched:
              </span>
              <span className="text-sm">{formatDate(last_watched)}</span>
            </div>
          </div>
        </CardContent>
      </Card>

      {/* Series Episode Statistics - Only show for Series */}
      {item.type === "Series" && statistics.episode_stats && (
        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <Play className="w-5 h-5" />
              Episode Statistics
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-4">
            <div className="grid grid-cols-2 gap-4">
              <div className="flex flex-col">
                <span className="text-2xl font-bold text-primary">
                  {statistics.episode_stats.total_seasons}
                </span>
                <span className="text-sm text-muted-foreground">
                  Total Seasons
                </span>
              </div>
              <div className="flex flex-col">
                <span className="text-2xl font-bold text-primary">
                  {statistics.episode_stats.total_episodes}
                </span>
                <span className="text-sm text-muted-foreground">
                  Total Episodes
                </span>
              </div>
            </div>

            <div className="grid grid-cols-2 gap-4">
              <div className="flex flex-col">
                <div className="flex items-center gap-1">
                  <CheckCircle className="w-4 h-4" />
                  <span className="text-lg font-semibold">
                    {statistics.episode_stats.watched_seasons}
                  </span>
                </div>
                <span className="text-sm text-muted-foreground">
                  Watched Seasons
                </span>
              </div>
              <div className="flex flex-col">
                <div className="flex items-center gap-1">
                  <CheckCircle className="w-4 h-4" />
                  <span className="text-lg font-semibold">
                    {statistics.episode_stats.watched_episodes}
                  </span>
                </div>
                <span className="text-sm text-muted-foreground">
                  Watched Episodes
                </span>
              </div>
            </div>
          </CardContent>
        </Card>
      )}

      {/* Technical Details */}
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <Video className="w-5 h-5" />
            Technical Details
          </CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="grid grid-cols-1 gap-3">
            {item.container && (
              <div className="flex items-center justify-between">
                <span className="text-sm text-muted-foreground">
                  Container:
                </span>
                <Badge variant="outline">{item.container.toUpperCase()}</Badge>
              </div>
            )}

            {item.width && item.height && (
              <div className="flex items-center justify-between">
                <span className="text-sm text-muted-foreground">
                  Resolution:
                </span>
                <Badge variant="outline">
                  {item.width}×{item.height}
                </Badge>
              </div>
            )}

            {item.hasSubtitles !== null && (
              <div className="flex items-center justify-between">
                <span className="text-sm text-muted-foreground">
                  Subtitles:
                </span>
                <Badge variant={item.hasSubtitles ? "default" : "secondary"}>
                  {item.hasSubtitles ? "Available" : "None"}
                </Badge>
              </div>
            )}

            {item.videoType && (
              <div className="flex items-center justify-between">
                <span className="text-sm text-muted-foreground">
                  Video Type:
                </span>
                <Badge variant="outline">{item.videoType}</Badge>
              </div>
            )}

            {item.premiereDate && (
              <div className="flex items-center justify-between">
                <span className="text-sm text-muted-foreground">Premiere:</span>
                <span className="text-sm">
                  {new Intl.DateTimeFormat("en-US", {
                    year: "numeric",
                    month: "long",
                    day: "numeric",
                  }).format(new Date(item.premiereDate))}
                </span>
              </div>
            )}
          </div>
        </CardContent>
      </Card>

      {/* Tags */}
      {item.tags && item.tags.length > 0 && (
        <Card className="lg:col-span-2">
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <Tag className="w-5 h-5" />
              Tags
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="flex flex-wrap gap-2">
              {item.tags.map((tag) => (
                <Badge key={tag} variant="secondary">
                  {tag}
                </Badge>
              ))}
            </div>
          </CardContent>
        </Card>
      )}
    </div>
  );
}
