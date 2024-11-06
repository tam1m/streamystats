"use client";

import * as React from "react";
import { Bar, BarChart, CartesianGrid, XAxis, YAxis } from "recharts";

import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import {
  ChartConfig,
  ChartContainer,
  ChartTooltip,
  ChartTooltipContent,
} from "@/components/ui/chart";
import { Statistics } from "@/lib/db";
import { formatDuration } from "@/lib/utils";

const chartConfig = {
  minutes: {
    label: "Minutes",
    color: "hsl(var(--chart-1))",
  },
} satisfies ChartConfig;

interface Props {
  data: Statistics["average_watchtime_per_week_day"];
}

const dayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];

export const WatchTimePerWeekDay: React.FC<Props> = ({ data }) => {
  const formattedData = React.useMemo(() => {
    return data
      .map((item) => ({
        day: dayNames[item.day_of_week - 1],
        minutes: Math.floor(item.average_duration / 60),
        dayNumber: item.day_of_week,
      }))
      .sort((a, b) => a.dayNumber - b.dayNumber);
  }, [data]);

  return (
    <Card>
      <CardHeader className="flex items-center gap-2 space-y-0 border-b py-5 sm:flex-row">
        <div className="grid flex-1 gap-1 text-center sm:text-left">
          <CardTitle>Average Watch Time Per Day of Week</CardTitle>
          <CardDescription>
            Showing average watch time for each day of the week
          </CardDescription>
        </div>
      </CardHeader>
      <CardContent className="px-2 pt-4 sm:px-6 sm:pt-6">
        <ChartContainer
          config={chartConfig}
          className="aspect-auto h-[250px] w-full"
        >
          <BarChart data={formattedData}>
            <CartesianGrid vertical={false} />
            <XAxis
              dataKey="day"
              tickLine={false}
              axisLine={false}
              tickMargin={8}
            />
            <YAxis
              tickLine={false}
              axisLine={false}
              tickMargin={8}
              tickFormatter={(value) => `${value}m`}
            />
            <ChartTooltip
              cursor={false}
              content={
                <ChartTooltipContent
                  formatter={(m) => (
                    <div className="flex flex-row items-center justify-between w-full">
                      <p>Time</p>
                      <p>{formatDuration(Number(m), "minutes")}</p>
                    </div>
                  )}
                  hideLabel
                />
              }
            />
            <Bar dataKey="minutes" fill="#2761D9" radius={8} name="Minutes" />
          </BarChart>
        </ChartContainer>
      </CardContent>
    </Card>
  );
};
