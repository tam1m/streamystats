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
  startEmbedding,
  stopEmbedding,
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
import { Loader, Play, Square } from "lucide-react";

export function EmbeddingsManager({ server }: { server: Server }) {
  const [apiKey, setApiKey] = useState(server.open_ai_api_token || "");
  const [isSaving, setIsSaving] = useState(false);
  const [isStarting, setIsStarting] = useState(false);
  const [isStopping, setIsStopping] = useState(false);
  const [isClearing, setIsClearing] = useState(false);
  const [showClearDialog, setShowClearDialog] = useState(false);

  const {
    data: progress,
    error,
    isLoading,
    refetch,
  } = useQuery<EmbeddingProgress>({
    queryKey: ["embedding-progress", server.id],
    queryFn: async () => await getEmbeddingProgress(server.id),
    refetchInterval: 1000, // Poll every second
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
      toast.success("API Key saved successfully");
      refetch();
    } catch (error) {
      toast.error("Failed to save API key");
    } finally {
      setIsSaving(false);
    }
  };

  const handleStartEmbedding = async () => {
    setIsStarting(true);
    try {
      const result = await startEmbedding(server.id);
      toast.success(result.message);
      refetch();
    } catch (err) {
      toast.error(
        err instanceof Error ? err.message : "Failed to start embedding process"
      );
    } finally {
      setIsStarting(false);
    }
  };

  const handleStopEmbedding = async () => {
    setIsStopping(true);
    try {
      const result = await stopEmbedding(server.id);
      toast.success(result.message);
      refetch();
    } catch (err) {
      toast.error(
        err instanceof Error ? err.message : "Failed to stop embedding process"
      );
    } finally {
      setIsStopping(false);
    }
  };

  const handleClearEmbeddings = async () => {
    setIsClearing(true);
    try {
      const result = await clearEmbeddings(server.id);
      toast.success(result.message);
      refetch();
    } catch (err) {
      toast.error(
        err instanceof Error ? err.message : "Failed to clear embeddings"
      );
    } finally {
      setIsClearing(false);
      setShowClearDialog(false);
    }
  };

  // Helper to get status text
  const getStatusText = (status: string) => {
    switch (status) {
      case "idle":
        return "Idle";
      case "starting":
        return "Starting embedding process...";
      case "processing":
        return "Generating embeddings for movies...";
      case "completed":
        return "All requested movies have embeddings";
      case "failed":
        return "Process failed. Please try again.";
      case "stopped":
        return "Process was stopped";
      default:
        return status.charAt(0).toUpperCase() + status.slice(1);
    }
  };

  // Check if the process is actively running
  const isProcessRunning =
    progress?.status === "processing" || progress?.status === "starting";

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
              <Button onClick={handleSaveApiKey} disabled={isSaving || !apiKey}>
                {isSaving ? "Saving..." : "Save API Key"}
              </Button>
            </div>
          </div>

          <Separator />

          <div className="space-y-4">
            <h3 className="text-sm font-medium">Movie Embeddings</h3>
            <div className="flex justify-between mb-2">
              <span className="text-sm font-medium">
                Status: {getStatusText(progress?.status || "idle")}
              </span>
              <span className="text-sm text-muted-foreground">
                {progress?.processed || 0} of {progress?.total || 0} movies
                embedded
                {progress?.total > 0
                  ? ` (${progress.percentage.toFixed(1)}%)`
                  : ""}
              </span>
            </div>

            <Progress value={progress?.percentage || 0} className="h-2" />

            <div className="flex gap-2 mt-4">
              <Button
                onClick={handleStartEmbedding}
                disabled={
                  isStarting || isProcessRunning || !server.open_ai_api_token
                }
                className="flex items-center gap-1"
              >
                {isStarting ? (
                  <>
                    <Loader className="h-4 w-4 animate-spin" /> Starting...
                  </>
                ) : (
                  <>
                    <Play className="h-4 w-4" /> Start Embedding
                  </>
                )}
              </Button>

              <Button
                onClick={handleStopEmbedding}
                disabled={isStopping || !isProcessRunning}
                variant="secondary"
                className="flex items-center gap-1"
              >
                {isStopping ? (
                  <>
                    <Loader className="h-4 w-4 animate-spin" /> Stopping...
                  </>
                ) : (
                  <>
                    <Square className="h-4 w-4" /> Stop Embedding
                  </>
                )}
              </Button>
            </div>

            {error && (
              <div className="text-sm text-red-500 mt-2">
                Error fetching progress. Retrying...
              </div>
            )}
          </div>

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
              disabled={isClearing || isProcessRunning}
            >
              {isClearing ? "Clearing..." : "Clear All Embeddings"}
            </Button>
          </div>
        </CardContent>
      </Card>

      <AlertDialog open={showClearDialog} onOpenChange={setShowClearDialog}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Are you absolutely sure?</AlertDialogTitle>
            <AlertDialogDescription>
              This action will delete all existing movie embeddings. You will
              need to regenerate them if you want to use AI-powered
              recommendations.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancel</AlertDialogCancel>
            <AlertDialogAction
              onClick={(e) => {
                e.preventDefault();
                handleClearEmbeddings();
              }}
              className="bg-destructive text-destructive-foreground hover:bg-destructive/90"
            >
              {isClearing ? "Clearing..." : "Clear Embeddings"}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </>
  );
}
