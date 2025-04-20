"use client";

import {
  Accordion,
  AccordionContent,
  AccordionItem,
  AccordionTrigger,
} from "@/components/ui/accordion";
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { importJellystats } from "@/lib/importJellystats";
import {
  AlertCircle,
  CheckCircle2,
  HelpCircle,
  Info,
  Loader2,
  Upload,
} from "lucide-react";
import { useEffect, useRef, useState } from "react";
import { useFormState, useFormStatus } from "react-dom";

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

          <div className="space-y-2 flex flex-col">
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

        <Accordion type="single" collapsible className="mt-6">
          <AccordionItem value="instructions">
            <AccordionTrigger className="flex items-center text-sm font-medium">
              <HelpCircle className="mr-2 h-4 w-4" />
              How to export data from Jellystats
            </AccordionTrigger>
            <AccordionContent>
              <div className="text-sm text-muted-foreground space-y-2 pt-2 pl-1">
                <ol className="list-decimal pl-5 space-y-1.5">
                  <li>Open your Jellystats instance</li>
                  <li>Navigate to Settings and select the Backup tab</li>
                  <li>
                    Select only <em className="font-semibold">Activity</em> (it
                    will appear purple when selected)
                  </li>
                  <li>Under settings click Settings</li>
                  <li>Scroll all the way to the end and start a backup</li>
                  <li>Navigate back to Backups</li>
                  <li>
                    Select Actions on the backup you just took once it is
                    visible and click Download
                  </li>
                  <li>Upload it here</li>
                </ol>
              </div>
            </AccordionContent>
          </AccordionItem>
        </Accordion>
      </CardContent>
    </Card>
  );
}
