"use client";

import { Button } from "@/components/ui/button";
import { clearEmbeddings } from "@/lib/db/server";
import { useState } from "react";
import { toast } from "sonner";

interface ClearEmbeddingsProps {
  serverId: number;
}

export function ClearEmbeddings({ serverId }: ClearEmbeddingsProps) {
  const [isClearing, setIsClearing] = useState(false);

  const handleClearEmbeddings = async () => {
    if (
      !confirm(
        "Are you sure you want to clear all embeddings? This action cannot be undone."
      )
    ) {
      return;
    }

    setIsClearing(true);
    try {
      const result = await clearEmbeddings(serverId);
      toast.success(result.message);
    } catch (err) {
      toast.error(
        err instanceof Error ? err.message : "Failed to clear embeddings"
      );
    } finally {
      setIsClearing(false);
    }
  };

  return (
    <Button
      variant="destructive"
      onClick={handleClearEmbeddings}
      disabled={isClearing}
    >
      {isClearing ? "Clearing..." : "Clear All Embeddings"}
    </Button>
  );
}
