"use client";

import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import {
  Card,
  CardContent,
  CardDescription,
  CardFooter,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Progress } from "@/components/ui/progress";
import { toast } from "sonner";
import {
  saveOpenAIKey,
  clearEmbeddings,
  getEmbeddingProgress,
  EmbeddingProgress,
} from "@/lib/db/server";
import { useQuery } from "@tanstack/react-query";
import { Separator } from "@/components/ui/separator";
import { Server } from "@/lib/db";
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "@/components/ui/alert-dialog";

export function EmbeddingsManager({ server }: { server: Server }) {
  const [apiKey, setApiKey] = useState(server.open_ai_api_token || "");
  const [isSaving, setIsSaving] = useState(false);
  const [isClearing, setIsClearing] = useState(false);
  const [showClearDialog, setShowClearDialog] = useState(false);

  const {
    data: progress,
    error,
    isLoading,
  } = useQuery<EmbeddingProgress>({
    queryKey: ["embedding-progress", server.id],
    queryFn: async () => await getEmbeddingProgress(server.id),
    refetchInterval: (query) => {
      const { data } = query.state;
      return data?.status === "processing" ? 2000 : false;
    },
    retry: 3,
    retryDelay: 1000,
    initialData: {
      total: 0,
      processed: 0,
      status: "idle" as const,
      percentage: 0,
    },
  });

  const handleSaveApiKey = async () => {
    setIsSaving(true);
    try {
      await saveOpenAIKey(server.id, apiKey);
      toast.success("API Key saved successfully. Embedding job started.");
    } catch (error) {
      toast.error("Failed to save API key");
    } finally {
      setIsSaving(false);
    }
  };

  const handleClearEmbeddings = async () => {
    setIsClearing(true);
    try {
      const result = await clearEmbeddings(server.id);
      toast.success(result.message);
    } catch (err) {
      toast.error(
        err instanceof Error ? err.message : "Failed to clear embeddings"
      );
    } finally {
      setIsClearing(false);
      setShowClearDialog(false);
    }
  };

  return (
    <>
      <Card className="w-full mb-6">
        <CardHeader>
          <CardTitle>AI & Embeddings</CardTitle>
          <CardDescription>
            Set an OpenAI API key to generate recommendations.
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-6">
          <div className="space-y-4">
            <h3 className="text-sm font-medium">OpenAI API Key</h3>
            <div className="flex gap-2">
              <Input
                type="password"
                placeholder="sk-..."
                value={apiKey}
                onChange={(e) => setApiKey(e.target.value)}
                className="flex-1"
              />
              <Button onClick={handleSaveApiKey} disabled={isSaving}>
                {isSaving ? "Saving..." : "Save and run"}
              </Button>
            </div>
          </div>

          {progress?.status !== "idle" || progress?.total > 0 ? (
            <div className="space-y-4">
              <Separator />
              <h3 className="text-sm font-medium">Movie Embeddings</h3>
              <Progress value={progress.percentage} />
              <div className="flex justify-between text-sm text-muted-foreground">
                <span>
                  {progress.processed} of {progress.total} movies embedded
                </span>
                <span>{progress.percentage.toFixed(1)}%</span>
              </div>
              <div className="text-sm text-muted-foreground">
                Status:{" "}
                {progress.status === "processing"
                  ? "Generating embeddings for movies..."
                  : progress.status === "completed"
                  ? "All requested movies have embeddings"
                  : progress.status.charAt(0).toUpperCase() +
                    progress.status.slice(1)}
              </div>
              {error && (
                <div className="text-sm text-red-500">
                  Error fetching progress. Retrying...
                </div>
              )}
            </div>
          ) : null}

          <Separator />
          <div className="space-y-4">
            <h3 className="text-sm font-medium">Clear Embeddings</h3>
            <p className="text-sm text-muted-foreground">
              Clearing embeddings will remove all existing embeddings and
              require re-processing.
            </p>
            <Button
              variant="destructive"
              onClick={() => setShowClearDialog(true)}
              disabled={isClearing || progress?.status === "processing"}
            >
              {isClearing ? "Clearing..." : "Clear All Embeddings"}
            </Button>
          </div>
        </CardContent>
      </Card>

      <AlertDialog open={showClearDialog} onOpenChange={setShowClearDialog}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Clear All Embeddings</AlertDialogTitle>
            <AlertDialogDescription>
              Are you sure you want to clear all embeddings? This action cannot
              be undone.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancel</AlertDialogCancel>
            <AlertDialogAction onClick={handleClearEmbeddings}>
              Continue
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </>
  );
}
