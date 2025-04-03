"use client";

import * as React from "react";
import { Bar, BarChart, CartesianGrid, XAxis } from "recharts";
import { CalendarIcon } from "lucide-react";
import { format } from "date-fns";
import { useSearchParams } from "next/navigation";

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
import { Button } from "@/components/ui/button";
import { Calendar } from "@/components/ui/calendar";
import {
  Popover,
  PopoverContent,
  PopoverTrigger,
} from "@/components/ui/popover";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Statistics } from "@/lib/db";
import { formatDuration, cn } from "@/lib/utils";
import { useQueryParams } from "@/hooks/useQueryParams";

const chartConfig = {
  Episode: {
    label: "Episodes",
    color: "hsl(var(--chart-1))",
  },
  Movie: {
    label: "Movies",
    color: "hsl(var(--chart-5))",
  },
} satisfies ChartConfig;

interface Props {
  data: Statistics["watchtime_per_day"];
}

export const WatchTimeGraph: React.FC<Props> = ({ data }) => {
  const searchParams = useSearchParams();
  const { updateQueryParams } = useQueryParams();

  // Get date parameters from URL or set defaults
  const startDateParam = searchParams.get("startDate");
  const endDateParam = searchParams.get("endDate");
  const rangeParam = searchParams.get("range") || "90d";

  // Parse dates or set defaults
  const defaultEndDate = new Date();
  const getDefaultStartDate = () => {
    const date = new Date();
    if (rangeParam === "30d") {
      date.setDate(date.getDate() - 30);
    } else if (rangeParam === "7d") {
      date.setDate(date.getDate() - 7);
    } else {
      date.setDate(date.getDate() - 90);
    }
    return date;
  };

  const [startDate, setStartDate] = React.useState<Date | undefined>(
    startDateParam ? new Date(startDateParam) : getDefaultStartDate()
  );
  const [endDate, setEndDate] = React.useState<Date | undefined>(
    endDateParam ? new Date(endDateParam) : defaultEndDate
  );

  // Update the URL when dates change
  const handleDateChange = (type: "start" | "end", date?: Date) => {
    if (type === "start") {
      setStartDate(date);
      if (date) {
        updateQueryParams({
          startDate: date.toISOString().split("T")[0],
          range: null, // Clear the range when specific dates are selected
        });
      }
    } else {
      setEndDate(date);
      if (date) {
        updateQueryParams({
          endDate: date.toISOString().split("T")[0],
          range: null, // Clear the range when specific dates are selected
        });
      }
    }
  };

  // Handle range selection
  const handleRangeChange = (value: string) => {
    updateQueryParams({
      range: value,
      startDate: null, // Clear specific dates when using range
      endDate: null,
    });

    const end = new Date();
    const start = new Date();

    if (value === "30d") {
      start.setDate(start.getDate() - 30);
    } else if (value === "7d") {
      start.setDate(start.getDate() - 7);
    } else {
      start.setDate(start.getDate() - 90);
    }

    setStartDate(start);
    setEndDate(end);
  };

  const filteredData = React.useMemo(() => {
    const formattedData = data.map((item) => ({
      date: new Date(item.date).toISOString().split("T")[0],
      Movie: Math.floor(
        (item.watchtime_by_type.find((i) => i.item_type === "Movie")
          ?.total_duration || 0) / 60
      ),
      Episode: Math.floor(
        (item.watchtime_by_type.find((i) => i.item_type === "Episode")
          ?.total_duration || 0) / 60
      ),
    }));

    const start = startDate || getDefaultStartDate();
    const end = endDate || defaultEndDate;

    const filteredData = formattedData.filter((item) => {
      const date = new Date(item.date);
      return date >= start && date <= end;
    });

    const result = [];
    for (let d = new Date(start); d <= end; d.setDate(d.getDate() + 1)) {
      const dateString = d.toISOString().split("T")[0];
      const existingData = filteredData.find(
        (item) => item.date === dateString
      );
      if (existingData) {
        result.push(existingData);
      } else {
        result.push({ date: dateString, Movie: 0, Episode: 0 });
      }
    }

    return result;
  }, [data, startDate, endDate]);

  return (
    <Card>
      <CardHeader className="flex md:items-center gap-2 space-y-0 border-b py-5 sm:flex-row p-4 md:p-6">
        <div className="grid flex-1 gap-1">
          <CardTitle>Watch Time Per Day</CardTitle>
          <CardDescription>
            Showing total watch time for the selected period
          </CardDescription>
        </div>
        <div className="mr-4">
          {Object.entries(chartConfig).map(([key, config]) => (
            <div key={key} className="flex items-center gap-2">
              <div
                className="w-2 h-2 rounded-[2px] mr-2"
                style={{ backgroundColor: config.color }}
              ></div>
              <p className="text-xs">{config.label}</p>
            </div>
          ))}
        </div>

        <div className="flex flex-col sm:flex-row gap-2">
          {/* Date range picker */}
          <div className="flex items-center gap-2">
            <Popover>
              <PopoverTrigger asChild>
                <Button
                  variant="outline"
                  className="w-[150px] justify-start text-left font-normal"
                >
                  <CalendarIcon className="mr-2 h-4 w-4" />
                  {startDate ? format(startDate, "MMM dd, yyyy") : "Start date"}
                </Button>
              </PopoverTrigger>
              <PopoverContent className="w-auto p-0">
                <Calendar
                  mode="single"
                  selected={startDate}
                  onSelect={(date) => handleDateChange("start", date)}
                  initialFocus
                  disabled={(date) =>
                    date > new Date() || (endDate ? date > endDate : false)
                  }
                />
              </PopoverContent>
            </Popover>

            <span className="text-muted-foreground">to</span>

            <Popover>
              <PopoverTrigger asChild>
                <Button
                  variant="outline"
                  className="w-[150px] justify-start text-left font-normal"
                >
                  <CalendarIcon className="mr-2 h-4 w-4" />
                  {endDate ? format(endDate, "MMM dd, yyyy") : "End date"}
                </Button>
              </PopoverTrigger>
              <PopoverContent className="w-auto p-0">
                <Calendar
                  mode="single"
                  selected={endDate}
                  onSelect={(date) => handleDateChange("end", date)}
                  initialFocus
                  disabled={(date) =>
                    date > new Date() || (startDate ? date < startDate : false)
                  }
                />
              </PopoverContent>
            </Popover>
          </div>

          {/* Preset ranges */}
          <Select value={rangeParam} onValueChange={handleRangeChange}>
            <SelectTrigger
              className="w-[160px] rounded-lg sm:ml-auto"
              aria-label="Select a time range"
            >
              <SelectValue placeholder="Presets" />
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
        </div>
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
              formatter={(value, name, item) => (
                <div className="flex flex-row items-center w-full">
                  <div
                    className="w-2 h-2 rounded-[2px] mr-2"
                    style={{ backgroundColor: item.color }}
                  ></div>
                  <p className="">{name}</p>
                  <p className="ml-auto">
                    {formatDuration(Number(value), "minutes")}
                  </p>
                </div>
              )}
              content={<ChartTooltipContent indicator="dashed" />}
            />
            <Bar
              dataKey="Episode"
              fill={chartConfig.Episode.color}
              radius={[4, 4, 0, 0]}
              name="Episode"
            />
            <Bar
              dataKey="Movie"
              fill={chartConfig.Movie.color}
              radius={[4, 4, 0, 0]}
              name="Movie"
            />
          </BarChart>
        </ChartContainer>
      </CardContent>
    </Card>
  );
};
