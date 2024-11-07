import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { formatDuration } from "@/lib/utils";
import React from "react";

interface TotalWatchTimeProps {
  data: number; // Assuming data is in seconds
}

const TotalWatchTime: React.FC<TotalWatchTimeProps> = ({ data }) => {
  return (
    <Card>
      <CardHeader>
        <CardTitle>Total Watch Time</CardTitle>
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
