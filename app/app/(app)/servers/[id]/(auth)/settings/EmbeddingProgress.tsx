"use client";

import { Progress } from "@/components/ui/progress";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { getEmbeddingProgress } from "@/lib/db/server";
import { useQuery } from "@tanstack/react-query";

export const EmbeddingProgress = ({ serverId }: { serverId: number }) => {
  const {
    data: progress = {
      total: 0,
      processed: 0,
      status: "idle" as const,
      percentage: 0,
    },
    error,
    isLoading,
  } = useQuery({
    queryKey: ["embedding-progress", serverId],
    queryFn: async () => {
      const data = await getEmbeddingProgress(serverId);
      return data;
    },
    refetchInterval: 2000, // Poll every 2 seconds
    retry: 3, // Retry failed requests 3 times
    retryDelay: 1000, // Wait 1 second between retries
  });

  // Log any errors
  if (error) {
    console.error("Error fetching embedding progress:", error);
  }

  // Don't show the card if there's no embedding in progress
  if (progress.status === "idle" && progress.total === 0) {
    return null;
  }

  return (
    <Card className="w-full">
      <CardHeader>
        <CardTitle>Embedding Progress</CardTitle>
        <CardDescription>
          Progress of generating embeddings for your media items
        </CardDescription>
      </CardHeader>
      <CardContent>
        <div className="space-y-4">
          <Progress value={progress.percentage} />
          <div className="flex justify-between text-sm text-muted-foreground">
            <span>
              {progress.processed} of {progress.total} items processed
            </span>
            <span>{progress.percentage.toFixed(1)}%</span>
          </div>
          <div className="text-sm text-muted-foreground">
            Status:{" "}
            {progress.status.charAt(0).toUpperCase() + progress.status.slice(1)}
          </div>
          {error && (
            <div className="text-sm text-red-500">
              Error fetching progress. Retrying...
            </div>
          )}
        </div>
      </CardContent>
    </Card>
  );
};
