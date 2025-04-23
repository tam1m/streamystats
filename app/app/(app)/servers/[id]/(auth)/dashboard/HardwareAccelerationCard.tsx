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
import { CategoryStat } from "@/lib/db/transcoding-statistics";
import { ZapIcon } from "lucide-react";
import {
  Bar,
  BarChart,
  CartesianGrid,
  LabelList,
  XAxis,
  YAxis,
} from "recharts";

type Props = {
  data: CategoryStat[];
};

export const HardwareAccelerationCard = ({ data }: Props) => {
  const getBarHeight = (dataLength: number) => {
    const minHeightPerBar = 30;
    const maxHeightPerBar = 40;
    return Math.min(
      Math.max(minHeightPerBar, 200 / dataLength),
      maxHeightPerBar
    );
  };

  const hwAccelData = data.map((item) => ({
    name: item.value,
    count: item.count,
  }));

  const hwAccelConfig = {
    count: {
      label: "Count",
      color: "hsl(var(--chart-1))",
    },
    label: {
      color: "hsl(var(--background))",
    },
  } satisfies ChartConfig;

  return (
    <Card>
      <CardHeader>
        <CardTitle>Hardware Acceleration</CardTitle>
        <CardDescription>
          Acceleration types used for transcoding
        </CardDescription>
      </CardHeader>
      <CardContent>
        <ChartContainer config={hwAccelConfig} className="h-[200px]">
          <BarChart
            accessibilityLayer
            data={hwAccelData}
            layout="vertical"
            margin={{
              right: 16,
              left: 0,
              top: 5,
              bottom: 5,
            }}
            barSize={getBarHeight(hwAccelData.length)}
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
          <ZapIcon className="h-4 w-4" />
          Primary acceleration: {data[0]?.value || "None"}
        </div>
      </CardFooter>
    </Card>
  );
};
