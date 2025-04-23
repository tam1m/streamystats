"use client";

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
import { NumericStat } from "@/lib/db/transcoding-statistics";
import { ZapIcon } from "lucide-react";
import {
  Bar,
  BarChart,
  CartesianGrid,
  LabelList,
  XAxis,
  YAxis,
} from "recharts";

interface BitrateDistributionCardProps {
  data: NumericStat;
}

export const BitrateDistributionCard = ({
  data,
}: BitrateDistributionCardProps) => {
  const formatBitrate = (value: number | null) => {
    if (value === null) return "0 Mbps";
    return `${(value / 1000000).toFixed(1)} Mbps`;
  };

  // Use all distribution categories, even those with zero count
  // to show the complete range of possible bitrates
  const bitrateData = data.distribution;

  const bitrateConfig = {
    count: {
      label: "Count",
      color: "hsl(var(--chart-3))",
    },
    label: {
      color: "hsl(var(--background))",
    },
  } satisfies ChartConfig;

  const getBarHeight = (dataLength: number) => {
    // Adjust for a fixed number of categories, to keep bar sizes consistent
    const fixedLength = Math.max(dataLength, 3); // Use at least 3 as divisor
    const minHeightPerBar = 25;
    const maxHeightPerBar = 35;
    return Math.min(
      Math.max(minHeightPerBar, 200 / fixedLength),
      maxHeightPerBar
    );
  };

  // Find categories with data for the footer
  const categoriesWithData = bitrateData
    .filter((item) => item.count > 0)
    .sort((a, b) => b.count - a.count);

  const mostCommonCategory =
    categoriesWithData.length > 0 ? categoriesWithData[0].range : "N/A";

  return (
    <Card>
      <CardHeader>
        <CardTitle>Bitrate Distribution</CardTitle>
        <CardDescription>
          Avg: {formatBitrate(data.avg ?? 0)} | Min: {formatBitrate(data.min)} |
          Max: {formatBitrate(data.max)}
        </CardDescription>
      </CardHeader>
      <CardContent>
        <ChartContainer config={bitrateConfig} className="h-[200px]">
          <BarChart
            accessibilityLayer
            data={bitrateData}
            layout="vertical"
            margin={{
              right: 16,
              left: 0,
              top: 5,
              bottom: 5,
            }}
            barSize={getBarHeight(bitrateData.length)}
          >
            <CartesianGrid horizontal={false} />
            <YAxis
              dataKey="range"
              type="category"
              tickLine={false}
              tickMargin={10}
              axisLine={false}
              hide
            />
            <XAxis dataKey="count" type="number" hide />
            <ChartTooltip
              cursor={false}
              content={<ChartTooltipContent indicator="line" />}
            />
            <Bar
              dataKey="count"
              layout="vertical"
              radius={4}
              className="fill-blue-600"
            >
              <LabelList
                dataKey="range"
                position="insideLeft"
                offset={8}
                className="fill-[#d6e3ff]"
                fontSize={12}
              />
              <LabelList
                dataKey="count"
                position="right"
                offset={8}
                className="fill-[#d6e3ff]"
                fontSize={12}
              />
            </Bar>
          </BarChart>
        </ChartContainer>
      </CardContent>
      <CardFooter className="text-sm text-muted-foreground">
        <div className="flex items-center gap-2">
          <ZapIcon className="h-4 w-4" />
          Most common: {mostCommonCategory}
        </div>
      </CardFooter>
    </Card>
  );
};
