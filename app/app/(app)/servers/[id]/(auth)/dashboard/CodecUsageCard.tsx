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
import {
  BarChart,
  Bar,
  XAxis,
  YAxis,
  CartesianGrid,
  LabelList,
} from "recharts";
import { FileDigit } from "lucide-react";
import { CategoryStat } from "@/lib/db/transcoding-statistics";

export const CodecUsageCard = ({
  videoCodecs,
  audioCodecs,
}: {
  videoCodecs: CategoryStat[];
  audioCodecs: CategoryStat[];
}) => {
  const codecData = [
    ...videoCodecs.map((item) => ({
      name: `Video: ${item.value}`,
      count: item.count,
    })),
    ...audioCodecs.map((item) => ({
      name: `Audio: ${item.value}`,
      count: item.count,
    })),
  ];

  const codecConfig = {
    count: {
      label: "Count",
      color: "hsl(var(--chart-2))",
    },
    label: {
      color: "hsl(var(--background))",
    },
  } satisfies ChartConfig;

  // Calculate bar height based on number of items
  const getBarHeight = (dataLength: number) => {
    const minHeightPerBar = 30;
    const maxHeightPerBar = 40;
    return Math.min(
      Math.max(minHeightPerBar, 200 / dataLength),
      maxHeightPerBar
    );
  };

  return (
    <Card>
      <CardHeader>
        <CardTitle>Codec Usage</CardTitle>
        <CardDescription>Video and audio codec distribution</CardDescription>
      </CardHeader>
      <CardContent>
        <ChartContainer config={codecConfig} className="h-[200px]">
          <BarChart
            accessibilityLayer
            data={codecData}
            layout="vertical"
            margin={{
              right: 16,
              left: 0,
              top: 5,
              bottom: 5,
            }}
            barSize={getBarHeight(codecData.length)}
          >
            <CartesianGrid horizontal={false} />
            <YAxis
              dataKey="name"
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
                dataKey="name"
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
          <FileDigit className="h-4 w-4" />
          Video: {videoCodecs[0]?.value || "N/A"}, Audio:{" "}
          {audioCodecs[0]?.value || "N/A"}
        </div>
      </CardFooter>
    </Card>
  );
};
