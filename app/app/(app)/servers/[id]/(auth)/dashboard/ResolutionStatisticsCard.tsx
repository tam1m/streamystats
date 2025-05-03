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
import { InfoIcon } from "lucide-react";
import {
  Bar,
  BarChart,
  CartesianGrid,
  LabelList,
  XAxis,
  YAxis,
} from "recharts";
import { CustomBarLabel, CustomValueLabel } from "@/components/ui/CustomBarLabel";

interface Props {
  width: NumericStat;
  height: NumericStat;
}

export const ResolutionStatisticsCard = ({ width, height }: Props) => {
  const getBarHeight = (dataLength: number) => {
    const minHeightPerBar = 30;
    const maxHeightPerBar = 40;
    return Math.min(
      Math.max(minHeightPerBar, 200 / dataLength),
      maxHeightPerBar
    );
  };

  const resolutionWidthData = width.distribution.filter((d) => d.count > 0);

  const resolutionConfig = {
    count: {
      label: "Count",
      color: "hsl(var(--chart-5))",
    },
    label: {
      color: "hsl(var(--background))",
    },
  } satisfies ChartConfig;

  const maxCount = Math.max(...resolutionWidthData.map((d) => d.count));

  return (
    <Card>
      <CardHeader>
        <CardTitle>Resolution Statistics</CardTitle>
        <CardDescription>
          Avg: {width.avg?.toFixed(0)}×{height.avg?.toFixed(0)}
        </CardDescription>
      </CardHeader>
      <CardContent>
        <ChartContainer config={resolutionConfig} className="h-[200px]">
          <BarChart
            accessibilityLayer
            data={resolutionWidthData}
            layout="vertical"
            margin={{
              right: 16,
              left: 0,
              top: 5,
              bottom: 5,
            }}
            barSize={getBarHeight(resolutionWidthData.length)}
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
                content={<CustomBarLabel fill="#d6e3ff" fontSize={12} />}
              />
              <LabelList
                dataKey="count"
                content={({ x, y, width, height, value }) =>
                  Number(value) === 0 ? null : (
                    <CustomValueLabel
                      x={Number(x)}
                      y={Number(y)}
                      width={Number(width)}
                      height={Number(height)}
                      value={value}
                      fill="#d6e3ff"
                      fontSize={12}
                      isMax={value === maxCount}
                    />
                  )
                }
              />
            </Bar>
          </BarChart>
        </ChartContainer>
      </CardContent>
      <CardFooter className="text-sm text-muted-foreground">
        <div className="flex items-center gap-2">
          <InfoIcon className="h-4 w-4" />
          Most common:{" "}
          {resolutionWidthData.sort((a, b) => b.count - a.count)[0]?.range ||
            "N/A"}
        </div>
      </CardFooter>
    </Card>
  );
};
