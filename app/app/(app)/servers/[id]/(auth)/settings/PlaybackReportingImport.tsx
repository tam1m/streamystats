"use client";

import {
  Accordion,
  AccordionContent,
  AccordionItem,
  AccordionTrigger,
} from "@/components/ui/accordion";
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "@/components/ui/alert-dialog"; // Import AlertDialog components
import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { importPlaybackReporting } from "@/lib/importPlaybackReporting";
import {
  AlertCircle,
  AlertTriangle, // Import warning icon
  CheckCircle2,
  HelpCircle,
  Info,
  Loader2,
  Upload,
} from "lucide-react";
import { useEffect, useRef, useState } from "react";
import { useFormState, useFormStatus } from "react-dom";

// Form submit button with loading state (remains the same)
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

export default function PlaybackReportingImport({
  serverId,
}: {
  serverId: number;
}) {
  const [selectedFile, setSelectedFile] = useState<File | null>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);
  const formRef = useRef<HTMLFormElement>(null); // Ref for the form
  const [isConfirmOpen, setIsConfirmOpen] = useState(false); // State for dialog

  const [state, formAction] = useFormState(importPlaybackReporting, {
    type: null,
    message: "",
  });

  // Handle file selection
  const handleFileChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    if (e.target.files && e.target.files.length > 0) {
      const file = e.target.files[0];
      if (
        file.type === "application/json" ||
        file.name.endsWith(".json") ||
        file.type === "text/tab-separated-values" ||
        file.name.endsWith(".tsv") ||
        file.name.endsWith(".txt")
      ) {
        setSelectedFile(file);
      } else {
        setSelectedFile(null);
        // Reset the file input
        if (fileInputRef.current) {
          fileInputRef.current.value = "";
        }
        // Optionally show an error message for invalid file type
      }
    } else {
      setSelectedFile(null);
    }
  };

  // Reset the form and close dialog after a successful upload
  useEffect(() => {
    if (state.type === "success") {
      setSelectedFile(null);
      if (fileInputRef.current) {
        fileInputRef.current.value = "";
      }
      setIsConfirmOpen(false); // Close dialog on success
    }
    // Optionally close dialog on error too, or leave it open
    // if (state.type === "error") {
    //   setIsConfirmOpen(false);
    // }
  }, [state]);

  // Handle form submission: prevent default and open dialog
  const handleSubmit = (e: React.FormEvent<HTMLFormElement>) => {
    // Only proceed if a file is selected (button should be enabled)
    if (selectedFile) {
      e.preventDefault(); // Stop the default form submission
      setIsConfirmOpen(true); // Open the confirmation dialog
    }
    // If no file is selected, the button is disabled, so this handler
    // shouldn't technically run, but this prevents accidental submission.
  };

  // Handle the confirmation action in the dialog
  const handleConfirmSubmit = () => {
    // Programmatically submit the form using the formAction
    // This ensures the useFormStatus hook works correctly
    formRef.current?.requestSubmit();
    // Dialog will close automatically via onOpenChange if needed,
    // but closing it manually here is fine too.
    // setIsConfirmOpen(false); // Let onOpenChange handle it or success useEffect
  };

  return (
    <Card className="w-full">
      <CardHeader>
        <CardTitle className="text-xl">
          Import from Playback Reporting
        </CardTitle>
        <CardDescription>
          Import your playback history from a Playback Reporting export file
          (JSON or TSV format)
        </CardDescription>
      </CardHeader>
      <CardContent>
        {/* Bind ref and onSubmit handler to the form */}
        <form
          ref={formRef}
          action={formAction}
          onSubmit={handleSubmit}
          className="space-y-4"
        >
          {/* Hidden input for server ID */}
          <input type="hidden" name="serverId" value={serverId} />

          <div className="space-y-2 flex flex-col">
            <label
              htmlFor="playback-reporting-file"
              className="text-sm font-medium"
            >
              Playback Reporting Export File
            </label>
            <Input
              ref={fileInputRef}
              id="playback-reporting-file"
              name="file"
              type="file"
              accept=".json,application/json,.tsv,text/tab-separated-values,.txt"
              onChange={handleFileChange}
              className="cursor-pointer"
              required // Make file input required for form validity
            />
            {selectedFile && (
              <p className="text-sm text-muted-foreground">
                Selected file: {selectedFile.name} (
                {(selectedFile.size / 1024 / 1024).toFixed(2)} MB)
              </p>
            )}
            {!selectedFile && fileInputRef.current?.files?.length === 0 && (
              <p className="text-sm text-destructive">
                Please select a .json or .tsv file.
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
            {/* SubmitButton now triggers the handleSubmit function which opens the dialog */}
            <SubmitButton hasFile={!!selectedFile} />
          </div>
        </form>

        <Accordion type="single" collapsible className="mt-6">
          <AccordionItem value="instructions">
            <AccordionTrigger className="flex items-center text-sm font-medium">
              <HelpCircle className="mr-2 h-4 w-4" />
              How to export data from Playback Reporting
            </AccordionTrigger>
            <AccordionContent>
              <div className="text-sm text-muted-foreground space-y-2 pt-2 pl-1">
                <ol className="list-decimal pl-5 space-y-1.5">
                  <li>Open your Jellyfin admin dashboard</li>
                  <li>Go to the Playback Reporting plugin settings</li>
                  <li>Click on Save Backup Data under the Backup section</li>
                  <li>Download the exported file</li>
                  <li>Upload it here</li>
                </ol>
              </div>
            </AccordionContent>
          </AccordionItem>
        </Accordion>

        {/* Confirmation Dialog */}
        <AlertDialog open={isConfirmOpen} onOpenChange={setIsConfirmOpen}>
          <AlertDialogContent>
            <AlertDialogHeader>
              <AlertDialogTitle className="flex items-center">
                <AlertTriangle className="mr-2 h-5 w-5 text-yellow-500" />
                Confirm Import
              </AlertDialogTitle>
              <AlertDialogDescription>
                This process may take some time depending on the file size.
                Duplicate entries may occur if you already have data. This is
                due to a discrepancy between the Jellyfin Playback Reporting
                plugin and other session reporting sources. Please confirm you
                want to proceed with the import.
              </AlertDialogDescription>
            </AlertDialogHeader>
            <AlertDialogFooter>
              <AlertDialogCancel>Cancel</AlertDialogCancel>
              {/* Action button triggers the actual form submission */}
              <AlertDialogAction onClick={handleConfirmSubmit}>
                Proceed with Import
              </AlertDialogAction>
            </AlertDialogFooter>
          </AlertDialogContent>
        </AlertDialog>
      </CardContent>
    </Card>
  );
}
