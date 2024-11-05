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
import { extend } from "lodash";
import { cn } from "@/lib/utils";

const chartConfig = {
  watch_time: {
    label: "Watch_time",
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
            <ChartTooltip cursor={false} content={<ChartTooltipContent />} />
            <PolarAngleAxis dataKey="genre" />
            <PolarGrid />
            <Radar
              dataKey="watch_time"
              fill="var(--color-watch_time)"
              fillOpacity={0.6}
            />
          </RadarChart>
        </ChartContainer>
      </CardContent>
    </Card>
  );
};
