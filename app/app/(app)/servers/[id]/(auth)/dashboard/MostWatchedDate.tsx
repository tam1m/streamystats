import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Statistics } from "@/lib/db";
import { formatDuration } from "@/lib/utils";
import { Calendar } from "lucide-react";
import React from "react";

const MostWatchedDate: React.FC<{ data: Statistics["most_watched_date"] }> = ({
  data,
}) => {
  if (!data) return null;

  const date = new Date(data.date);

  return (
    <Card className="flex-1">
      <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-0">
        <CardTitle className="text-sm font-medium">
          <p className="text-neutral-500">Most Active Day</p>
        </CardTitle>
        <Calendar className="h-4 w-4 text-muted-foreground" />
      </CardHeader>
      <CardContent>
        <div className="text-start">
          <p className="text-3xl font-bold">{formatDate(date)}</p>
          <p className="text-sm text-muted-foreground">
            {formatDuration(data.total_duration)} watched
          </p>
        </div>
      </CardContent>
    </Card>
  );
};

function formatDate(date: Date): string {
  return date.toLocaleDateString("en-US", {
    year: "numeric",
    month: "long",
    day: "numeric",
  });
}

export default MostWatchedDate;
