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
import { InfoIcon } from "lucide-react";
import { DirectnessStat } from "@/lib/db/transcoding-statistics";

interface DirectnessCardProps {
  data: DirectnessStat[];
}

export const DirectnessCard = ({ data }: DirectnessCardProps) => {
  const directnessConfig = {
    count: {
      label: "Count",
      color: "hsl(var(--chart-2))",
    },
    label: {
      color: "hsl(var(--background))",
    },
  } satisfies ChartConfig;

  const directnessData = data.map((item) => ({
    name: item.label,
    count: item.count,
  }));

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
        <CardTitle>Transcoding Directness</CardTitle>
        <CardDescription>
          How often content plays directly vs transcoded
        </CardDescription>
      </CardHeader>
      <CardContent>
        <ChartContainer config={directnessConfig} className="h-[200px]">
          <BarChart
            accessibilityLayer
            data={directnessData}
            layout="vertical"
            margin={{
              right: 16,
              left: 0,
              top: 5,
              bottom: 5,
            }}
            barSize={getBarHeight(directnessData.length)}
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
        {data.length > 0 ? (
          <div className="flex items-center gap-2">
            <InfoIcon className="h-4 w-4" />
            {data[0]?.label}: {data[0]?.percentage}%
          </div>
        ) : (
          <div>No transcoding data available</div>
        )}
      </CardFooter>
    </Card>
  );
};
