"use client";

import * as React from "react";
import { Bar, BarChart, CartesianGrid, XAxis } from "recharts";

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
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Statistics } from "@/lib/db";

const chartConfig = {
  minutes: {
    label: "Minutes",
    color: "hsl(var(--chart-1))",
  },
} satisfies ChartConfig;

interface Props {
  data: Statistics["watchtime_per_day"];
}

export const WatchTimeGraph: React.FC<Props> = ({ data }) => {
  const [timeRange, setTimeRange] = React.useState("90d");

  const filteredData = React.useMemo(() => {
    const formattedData = data.map((item) => ({
      date: new Date(item.date).toISOString().split("T")[0],
      minutes: Math.floor(item.total_duration / 60),
    }));

    const now = new Date();
    let daysToSubtract = 90;
    if (timeRange === "30d") {
      daysToSubtract = 30;
    } else if (timeRange === "7d") {
      daysToSubtract = 7;
    }
    const startDate = new Date(
      now.getTime() - daysToSubtract * 24 * 60 * 60 * 1000
    );

    const filteredData = formattedData.filter((item) => {
      const date = new Date(item.date);
      return date >= startDate && date <= now;
    });

    const result = [];
    for (let d = new Date(startDate); d <= now; d.setDate(d.getDate() + 1)) {
      const dateString = d.toISOString().split("T")[0];
      const existingData = filteredData.find(
        (item) => item.date === dateString
      );
      if (existingData) {
        result.push(existingData);
      } else {
        result.push({ date: dateString, minutes: 0 });
      }
    }

    return result;
  }, [data, timeRange]);

  return (
    <Card>
      <CardHeader className="flex items-center gap-2 space-y-0 border-b py-5 sm:flex-row">
        <div className="grid flex-1 gap-1 text-center sm:text-left">
          <CardTitle>Watch Time Per Day</CardTitle>
          <CardDescription>
            Showing total watch time for the selected period
          </CardDescription>
        </div>
        <Select value={timeRange} onValueChange={setTimeRange}>
          <SelectTrigger
            className="w-[160px] rounded-lg sm:ml-auto"
            aria-label="Select a time range"
          >
            <SelectValue placeholder="Last 3 months" />
          </SelectTrigger>
          <SelectContent className="rounded-xl">
            <SelectItem value="90d" className="rounded-lg">
              Last 3 months
            </SelectItem>
            <SelectItem value="30d" className="rounded-lg">
              Last 30 days
            </SelectItem>
            <SelectItem value="7d" className="rounded-lg">
              Last 7 days
            </SelectItem>
          </SelectContent>
        </Select>
      </CardHeader>
      <CardContent className="px-2 pt-4 sm:px-6 sm:pt-6">
        <ChartContainer
          config={chartConfig}
          className="aspect-auto h-[250px] w-full"
        >
          <BarChart data={filteredData}>
            <CartesianGrid vertical={false} />
            <XAxis
              dataKey="date"
              tickLine={false}
              axisLine={false}
              tickMargin={8}
              minTickGap={32}
              tickFormatter={(value) => {
                const date = new Date(value);
                return date.toLocaleDateString("en-US", {
                  month: "short",
                  day: "numeric",
                });
              }}
            />
            <ChartTooltip
              cursor={false}
              content={
                <ChartTooltipContent
                  labelFormatter={(value) => {
                    return new Date(value).toLocaleDateString("en-US", {
                      month: "short",
                      day: "numeric",
                    });
                  }}
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
