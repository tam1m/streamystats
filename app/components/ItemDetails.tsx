"use client";

import { Item } from "@/lib/db";
import { formatDuration } from "@/lib/utils";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar";
import {
  CalendarIcon,
  ClockIcon,
  UserIcon,
  BarChart3Icon,
  PlayIcon,
  CheckCircleIcon,
} from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { formatDistanceToNow } from "date-fns";
import { Progress } from "./ui/progress";

interface WatchHistoryItem {
  id: number;
  user_id: number;
  user_name: string;
  jellyfin_user_id: string;
  start_time: string;
  play_duration: number;
  percent_complete: number;
  completed: boolean;
  client_name: string;
  device_name: string;
}

interface UserWatched {
  user_id: number;
  jellyfin_user_id: string;
  user_name: string;
  view_count: number;
  total_watch_time: number;
  last_watched: string;
}

interface MonthlyStats {
  month: string;
  view_count: number;
  total_watch_time: number;
}

export interface ItemStatistics {
  item: Item;
  total_views: number;
  total_watch_time: number;
  completion_rate: number;
  first_watched: string | null;
  last_watched: string | null;
  users_watched: UserWatched[];
  watch_history: WatchHistoryItem[];
  watch_count_by_month: MonthlyStats[];
}

interface Props {
  item: Item;
  statistics: ItemStatistics;
}

export const ItemDetails: React.FC<Props> = ({ item, statistics }) => {
  return <div className="space-y-6">{item.name}</div>;
};
