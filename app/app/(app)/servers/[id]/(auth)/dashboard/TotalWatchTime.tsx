import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { formatDuration } from "@/lib/utils";
import { Clock } from "lucide-react";
import React from "react";

interface TotalWatchTimeProps {
  data: number; // Assuming data is in seconds
}

const TotalWatchTime: React.FC<TotalWatchTimeProps> = ({ data }) => {
  return (
    <Card className="flex-1">
      <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-0">
        <CardTitle className="text-sm font-medium">
          <p className="text-neutral-500">Total Watch Time</p>
        </CardTitle>
        <Clock className="h-4 w-4 text-muted-foreground" />
      </CardHeader>
      <CardContent>
        <div className="text-start">
          <p className="text-3xl font-bold">{formatDuration(data)}</p>
          <p className="text-sm text-muted-foreground">
            Total time spent watching
          </p>
        </div>
      </CardContent>
    </Card>
  );
};

export default TotalWatchTime;
