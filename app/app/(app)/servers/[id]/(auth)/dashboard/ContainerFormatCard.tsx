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
import { Layers } from "lucide-react";
import {
  CategoryStat,
  TranscodingStatisticsResponse,
} from "@/lib/db/transcoding-statistics";

interface ContainerFormatCardProps {
  data: CategoryStat[];
}

export const ContainerFormatCard = ({ data }: ContainerFormatCardProps) => {
  const containerData = data.map((item) => ({
    name: item.value,
    count: item.count,
  }));

  const containerConfig = {
    count: {
      label: "Count",
      color: "hsl(var(--chart-5))",
    },
    label: {
      color: "hsl(var(--background))",
    },
  } satisfies ChartConfig;

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
        <CardTitle>Container Format</CardTitle>
        <CardDescription>Media container distribution</CardDescription>
      </CardHeader>
      <CardContent>
        <ChartContainer config={containerConfig} className="h-[200px]">
          <BarChart
            accessibilityLayer
            data={containerData}
            layout="vertical"
            margin={{
              right: 16,
              left: 0,
              top: 5,
              bottom: 5,
            }}
            barSize={getBarHeight(containerData.length)}
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
          <Layers className="h-4 w-4" />
          Primary container: {data[0]?.value || "N/A"}
        </div>
      </CardFooter>
    </Card>
  );
};
