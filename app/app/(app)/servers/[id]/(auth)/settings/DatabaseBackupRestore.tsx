"use client";

import { useState } from "react";
import { useMutation } from "@tanstack/react-query";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { AlertCircle, Download, Upload } from "lucide-react";
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { toast } from "sonner";

export default function DatabaseBackupRestore({
  serverId,
}: {
  serverId: number;
}) {
  const [file, setFile] = useState<File | null>(null);

  const exportMutation = useMutation({
    mutationFn: async () => {
      const res = await fetch(`/api/servers/${serverId}/backup`, {
        method: "GET",
      });
      if (!res.ok) {
        const err = await res.json().catch(() => ({ error: "Unknown" }));
        throw new Error(err.error || "Export failed");
      }
      return res;
    },
    onSuccess: async (res) => {
      const cd = res.headers.get("content-disposition") ?? "";
      const m = cd.match(/filename="?([^"]+)"?/);
      const fn =
        m?.[1] ??
        `streamystat-backup-${new Date().toISOString().split("T")[0]}.db`;
      const blob = await res.blob();
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = fn;
      document.body.appendChild(a);
      a.click();
      a.remove();
      URL.revokeObjectURL(url);
      toast.success("Export complete");
    },
    onError: (e) => {
      toast.error(e instanceof Error ? e.message : "Export failed");
    },
  });

  const importMutation = useMutation({
    mutationFn: async () => {
      if (!file) throw new Error("Select a file first");
      const form = new FormData();
      form.set("file", file, file.name);
      const res = await fetch(`/api/servers/${serverId}/import`, {
        method: "POST",
        body: form,
      });
      const payload = await res.json().catch(() => ({
        error: "Invalid response",
      }));
      if (!res.ok) throw new Error(payload.error || "Import failed");
      return payload;
    },
    onSuccess: (data) => {
      toast.success(data.message || "Import succeeded");
      setFile(null);
    },
    onError: (e) => {
      toast.error(e instanceof Error ? e.message : "Import failed");
    },
  });

  return (
    <div className="space-y-6">
      <Card>
        <CardHeader>
          <CardTitle>Database Backup & Restore</CardTitle>
          <CardDescription>
            Export or restore your playback session data
          </CardDescription>
        </CardHeader>

        <CardContent className="space-y-6">
          {/* EXPORT */}
          <div className="space-y-2">
            <h3 className="text-lg font-medium">Export Sessions</h3>
            {exportMutation.isError && (
              <Alert variant="destructive">
                <AlertCircle className="h-4 w-4" />
                <AlertTitle>Error</AlertTitle>
                <AlertDescription>
                  {exportMutation.error instanceof Error
                    ? exportMutation.error.message
                    : "Export failed"}
                </AlertDescription>
              </Alert>
            )}
            <Button
              onClick={() => exportMutation.mutate()}
              disabled={exportMutation.isPending}
              className="flex items-center gap-2"
            >
              <Download className="h-4 w-4" />
              {exportMutation.isPending ? "Exporting..." : "Export Database"}
            </Button>
          </div>

          {/* IMPORT */}
          <div className="space-y-2">
            <h3 className="text-lg font-medium">Import Sessions</h3>
            {importMutation.isError && (
              <Alert variant="destructive">
                <AlertCircle className="h-4 w-4" />
                <AlertTitle>Error</AlertTitle>
                <AlertDescription>
                  {importMutation.error instanceof Error
                    ? importMutation.error.message
                    : "Import failed"}
                </AlertDescription>
              </Alert>
            )}
            <div className="flex flex-col items-start gap-4">
              <div>
                <Input
                  type="file"
                  accept=".db"
                  onChange={(e) => setFile(e.target.files?.[0] ?? null)}
                />
              </div>
              <Button
                onClick={() => importMutation.mutate()}
                disabled={importMutation.isPending || !file}
                className="flex items-center gap-2"
              >
                <Upload className="h-4 w-4" />
                {importMutation.isPending ? "Importing..." : "Import Database"}
              </Button>
            </div>
          </div>
        </CardContent>
      </Card>
    </div>
  );
}
