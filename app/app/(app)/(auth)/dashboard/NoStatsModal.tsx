"use client";

import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "@/components/ui/alert-dialog";
import { AlertDialogCancel } from "@radix-ui/react-alert-dialog";
import { useRouter } from "next/navigation";

export function NoStatsModal() {
  const router = useRouter();
  return (
    <AlertDialog open={true}>
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle>
            Run inital full sync task to get started
          </AlertDialogTitle>
          <AlertDialogDescription>
            This action is not optional. You need to sync statistics from your
            Jellyfin server. This will only take a minute.
          </AlertDialogDescription>
        </AlertDialogHeader>
        <AlertDialogFooter>
          <AlertDialogCancel>Done</AlertDialogCancel>
          <AlertDialogAction
            onClick={() => {
              router.push("/settings");
            }}
          >
            Continue to Settings
          </AlertDialogAction>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  );
}
