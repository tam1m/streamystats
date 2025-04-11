"use client";

import { TrendingUp } from "lucide-react";
import { PolarAngleAxis, PolarGrid, Radar, RadarChart } from "recharts";

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
        <ChartContainer config={chartConfig} className="mx-auto max-h-[250px]">
          <RadarChart data={data}>
            <ChartTooltip
              formatter={(val) => (
                <div>
                  <p>{formatDuration(Number(val))}</p>
                </div>
              )}
              cursor={false}
              content={<ChartTooltipContent />}
            />
            <PolarAngleAxis dataKey="genre" />
            <PolarGrid />
            <Radar
              dataKey="total_duration"
              fill="var(--color-total_duration)"
              fillOpacity={0.6}
              dot={{
                r: 4,
                fillOpacity: 1,
              }}
            />
          </RadarChart>
        </ChartContainer>
      </CardContent>
    </Card>
  );
};
