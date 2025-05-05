"use client";

import { TrendingUp } from "lucide-react";
import { PolarAngleAxis, PolarGrid, Radar, RadarChart, ResponsiveContainer } from "recharts";

import {
  Card,
  CardContent,
  CardDescription,
  CardFooter,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import {
  ChartConfig,
  ChartContainer,
  ChartTooltip,
  ChartTooltipContent,
} from "@/components/ui/chart";
import { GenreStat } from "@/lib/db";
import { cn, formatDuration } from "@/lib/utils";
import { extend } from "lodash";

const chartConfig = {
  total_duration: {
    label: "Total_duration",
    color: "hsl(var(--chart-1))",
  },
} satisfies ChartConfig;

interface Props extends React.HTMLAttributes<HTMLDivElement> {
  data: GenreStat[];
}

export const GenreStatsGraph: React.FC<Props> = ({
  data,
  className,
  ...props
}) => {
  return (
    <Card {...props} className={cn("", className)}>
      <CardHeader className="items-center pb-4">
        <CardTitle>Most Watched Genres</CardTitle>
        {/* <CardDescription>Showing most watched genres</CardDescription> */}
      </CardHeader>
      <CardContent className="pb-0">
        <ChartContainer config={chartConfig} className="h-[300px] w-full">
          <ResponsiveContainer width="100%" height="100%">
            <RadarChart data={data} outerRadius={90}>
              <PolarGrid />
              <PolarAngleAxis
                dataKey="genre"
                tick={{ fontSize: 12 }}
                tickLine={false}
              />
              <Radar
                name="Watch Time"
                dataKey="watch_time"
                stroke="hsl(var(--chart-1))"
                fill="hsl(var(--chart-1))"
                fillOpacity={0.6}
                dot={{
                  r: 4,
                  fillOpacity: 1,
                }}
              />
              <ChartTooltip
                formatter={(val) => (
                  <div>
                    <p>{formatDuration(Number(val))}</p>
                  </div>
                )}
                cursor={false}
                content={<ChartTooltipContent />}
              />
            </RadarChart>
          </ResponsiveContainer>
        </ChartContainer>
      </CardContent>
    </Card>
  );
};
