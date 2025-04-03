"use client";

import { useState, useRef, useEffect } from "react";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardFooter,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { Info, Upload, CheckCircle2, AlertCircle, Loader2 } from "lucide-react";
import { useFormState, useFormStatus } from "react-dom";
import { importJellystats } from "@/lib/importJellystats";

// Form submit button with loading state
function SubmitButton({ hasFile }: { hasFile: boolean }) {
  const { pending } = useFormStatus();

  return (
    <Button type="submit" disabled={pending || !hasFile} className="w-full">
      {pending ? (
        <>
          <Loader2 className="mr-2 h-4 w-4 animate-spin" />
          Uploading...
        </>
      ) : (
        <>
          <Upload className="mr-2 h-4 w-4" />
          Upload and Import
        </>
      )}
    </Button>
  );
}

export default function JellystatsImport({ serverId }: { serverId: number }) {
  const [selectedFile, setSelectedFile] = useState<File | null>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);

  const [state, formAction] = useFormState(importJellystats, {
    type: null,
    message: "",
  });

  // Handle file selection
  const handleFileChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    if (e.target.files && e.target.files.length > 0) {
      const file = e.target.files[0];
      if (file.type === "application/json" || file.name.endsWith(".json")) {
        setSelectedFile(file);
      } else {
        setSelectedFile(null);
        // Reset the file input
        if (fileInputRef.current) {
          fileInputRef.current.value = "";
        }
      }
    } else {
      setSelectedFile(null);
    }
  };

  // Reset the form after a successful upload
  useEffect(() => {
    if (state.type === "success" && fileInputRef.current) {
      setSelectedFile(null);
      fileInputRef.current.value = "";
    }
  }, [state]);

  return (
    <Card className="w-full">
      <CardHeader>
        <CardTitle className="text-xl">Import from Jellystats</CardTitle>
        <CardDescription>
          Import your playback history from a Jellystats JSON export file
        </CardDescription>
      </CardHeader>
      <CardContent>
        <form action={formAction} className="space-y-4">
          {/* Hidden input for server ID */}
          <input type="hidden" name="serverId" value={serverId} />

          <div className="space-y-2">
            <label htmlFor="jellystats-file" className="text-sm font-medium">
              Jellystats JSON Export File
            </label>
            <Input
              ref={fileInputRef}
              id="jellystats-file"
              name="file"
              type="file"
              accept=".json,application/json"
              onChange={handleFileChange}
              className="cursor-pointer"
            />
            {selectedFile && (
              <p className="text-sm text-muted-foreground">
                Selected file: {selectedFile.name} (
                {(selectedFile.size / 1024 / 1024).toFixed(2)} MB)
              </p>
            )}
          </div>

          {state?.type && (
            <Alert variant={state.type === "error" ? "destructive" : "default"}>
              {state.type === "success" && <CheckCircle2 className="h-4 w-4" />}
              {state.type === "error" && <AlertCircle className="h-4 w-4" />}
              {state.type === "info" && <Info className="h-4 w-4" />}
              <AlertTitle>
                {state.type === "success" && "Success"}
                {state.type === "error" && "Error"}
                {state.type === "info" && "Information"}
              </AlertTitle>
              <AlertDescription>{state.message}</AlertDescription>
            </Alert>
          )}

          <div className="pt-2">
            <SubmitButton hasFile={!!selectedFile} />
          </div>
        </form>
      </CardContent>
      <CardFooter className="flex flex-col items-start">
        <div className="text-sm text-muted-foreground space-y-2">
          <p className="font-medium">How to export data from Jellystats:</p>
          <ol className="list-decimal pl-5 space-y-1">
            <li>Open your Jellystats instance</li>
            <li>Navigate to Settings</li>
            <li>Click on Export Data</li>
            <li>Select JSON as the export format</li>
            <li>Download the file and upload it here</li>
          </ol>
        </div>
      </CardFooter>
    </Card>
  );
}
