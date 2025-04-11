"use client";

import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { ScrollArea } from "@/components/ui/scroll-area";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Library, User, startTautulliImportTask } from "@/lib/db";
import { useState } from "react";
import { toast } from "sonner";

type TautulliLibrary = {
  section_id: string;
  section_name: string;
  section_type: string;
  count: string;
};

type TautulliUser = {
  user_id: number;
  username: string;
  friendly_name: string;
  email: string;
  shared_libraries: string[];
};

type LibraryMapping = {
  tautulliLibraryId: string;
  jellyfinLibraryId: number | null;
};

type UserMapping = {
  tautulliUserId: number;
  jellyfinUserId: number | null;
};

interface TautulliMappingModalProps {
  tautulliLibraries: TautulliLibrary[];
  tautulliUsers: TautulliUser[];
  jellyfinLibraries: Library[];
  jellyfinUsers: User[];
  serverId: number;
}

export function TautulliMappingModal({
  tautulliLibraries,
  tautulliUsers,
  jellyfinLibraries,
  jellyfinUsers,
  serverId,
}: TautulliMappingModalProps) {
  const [libraryMappings, setLibraryMappings] = useState<LibraryMapping[]>([]);
  const [userMappings, setUserMappings] = useState<UserMapping[]>([]);
  const [tautulliUrl, setTautulliUrl] = useState<string>("");
  const [apiKey, setApiKey] = useState<string>("");
  const [isLoading, setIsLoading] = useState<boolean>(false);
  const [open, setOpen] = useState(false);

  const handleLibraryMappingChange = (
    tautulliLibraryId: string,
    jellyfinLibraryId: string | undefined,
  ) => {
    setLibraryMappings((prev) => {
      const newMappings = [...prev];
      const existingIndex = newMappings.findIndex(
        (mapping) => mapping.tautulliLibraryId === tautulliLibraryId,
      );

      if (existingIndex >= 0) {
        if (jellyfinLibraryId) {
          newMappings[existingIndex].jellyfinLibraryId =
            Number.parseInt(jellyfinLibraryId);
        } else {
          // If undefined, set to null
          newMappings[existingIndex].jellyfinLibraryId = null;
        }
      } else {
        newMappings.push({
          tautulliLibraryId,
          jellyfinLibraryId: jellyfinLibraryId
            ? Number.parseInt(jellyfinLibraryId)
            : null,
        });
      }

      return newMappings;
    });
  };

  const handleUserMappingChange = (
    tautulliUserId: number,
    jellyfinUserId: string | undefined,
  ) => {
    setUserMappings((prev) => {
      const newMappings = [...prev];
      const existingIndex = newMappings.findIndex(
        (mapping) => mapping.tautulliUserId === tautulliUserId,
      );

      if (existingIndex >= 0) {
        if (jellyfinUserId) {
          newMappings[existingIndex].jellyfinUserId =
            Number.parseInt(jellyfinUserId);
        } else {
          // If undefined, set to null
          newMappings[existingIndex].jellyfinUserId = null;
        }
      } else {
        newMappings.push({
          tautulliUserId,
          jellyfinUserId: jellyfinUserId
            ? Number.parseInt(jellyfinUserId)
            : null,
        });
      }

      return newMappings;
    });
  };

  const handleSubmit = async () => {
    if (!tautulliUrl) {
      toast.error("Please enter your Tautulli URL");
      return;
    }

    if (!apiKey) {
      toast.error("Please enter your Tautulli API key");
      return;
    }

    const validMappings = {
      libraryMappings: libraryMappings.filter(
        (m) => m.jellyfinLibraryId !== null,
      ),
      userMappings: userMappings.filter((m) => m.jellyfinUserId !== null),
    };

    try {
      setIsLoading(true);
      const stringMappings: Record<string, string> = {
        libraryMappings: JSON.stringify(validMappings.libraryMappings),
        userMappings: JSON.stringify(validMappings.userMappings),
      };

      await startTautulliImportTask(
        serverId,
        tautulliUrl,
        apiKey,
        stringMappings,
      );

      toast.success("Import started successfully");

      setOpen(false);
    } catch (error) {
      console.error("Import error:", error);
      toast.error("Failed to start import");
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button variant="outline">Import from Tautulli</Button>
      </DialogTrigger>
      <DialogContent className="sm:max-w-[700px]">
        <DialogHeader>
          <DialogTitle>Import Tautulli Data</DialogTitle>
          <DialogDescription>
            Import history data from Tautulli and map it to your Jellyfin
            libraries and users.
          </DialogDescription>
        </DialogHeader>

        <div className="grid gap-4 py-4">
          <div className="grid grid-cols-4 items-center gap-4">
            <Label htmlFor="tautulli-url" className="text-right">
              Tautulli URL
            </Label>
            <Input
              id="tautulli-url"
              placeholder="http://localhost:8181"
              className="col-span-3"
              value={tautulliUrl}
              onChange={(e) => setTautulliUrl(e.target.value)}
            />
          </div>
          <div className="grid grid-cols-4 items-center gap-4">
            <Label htmlFor="api-key" className="text-right">
              API Key
            </Label>
            <Input
              id="api-key"
              type="password"
              placeholder="Your Tautulli API key"
              className="col-span-3"
              value={apiKey}
              onChange={(e) => setApiKey(e.target.value)}
            />
          </div>
        </div>

        <Tabs defaultValue="libraries" className="w-full">
          <TabsList className="grid w-full grid-cols-2">
            <TabsTrigger value="libraries">Libraries</TabsTrigger>
            <TabsTrigger value="users">Users</TabsTrigger>
          </TabsList>
          <TabsContent value="libraries" className="mt-4">
            <ScrollArea className="h-[300px] pr-4">
              <div className="space-y-4">
                {tautulliLibraries.map((library) => (
                  <div
                    key={library.section_id}
                    className="grid grid-cols-2 gap-4 items-center"
                  >
                    <div>
                      <div className="font-medium">{library.section_name}</div>
                      <div className="text-sm text-muted-foreground">
                        {library.section_type} • {library.count} items
                      </div>
                    </div>
                    <Select
                      onValueChange={(value) =>
                        handleLibraryMappingChange(
                          library.section_id,
                          value || undefined,
                        )
                      }
                      value={
                        libraryMappings
                          .find(
                            (m) => m.tautulliLibraryId === library.section_id,
                          )
                          ?.jellyfinLibraryId?.toString() || undefined
                      }
                    >
                      <SelectTrigger>
                        <SelectValue placeholder="Select Jellyfin library" />
                      </SelectTrigger>
                      <SelectContent>
                        {jellyfinLibraries.map((jellyfinLib) => (
                          <SelectItem
                            key={jellyfinLib.id}
                            value={jellyfinLib.id.toString()}
                          >
                            {jellyfinLib.name} ({jellyfinLib.type})
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  </div>
                ))}
              </div>
            </ScrollArea>
          </TabsContent>
          <TabsContent value="users" className="mt-4">
            <ScrollArea className="h-[300px] pr-4">
              <div className="space-y-4">
                {tautulliUsers.map((user) => (
                  <div
                    key={user.user_id}
                    className="grid grid-cols-2 gap-4 items-center"
                  >
                    <div>
                      <div className="font-medium">
                        {user.friendly_name || user.username}
                      </div>
                      <div className="text-sm text-muted-foreground">
                        {user.email}
                        {user.shared_libraries && (
                          <span>
                            {" "}
                            • {user.shared_libraries.length} libraries
                          </span>
                        )}
                      </div>
                    </div>
                    <Select
                      onValueChange={(value) =>
                        handleUserMappingChange(
                          user.user_id,
                          value || undefined,
                        )
                      }
                      value={
                        userMappings
                          .find((m) => m.tautulliUserId === user.user_id)
                          ?.jellyfinUserId?.toString() || undefined
                      }
                    >
                      <SelectTrigger>
                        <SelectValue placeholder="Select Jellyfin user" />
                      </SelectTrigger>
                      <SelectContent>
                        {jellyfinUsers.map((jellyfinUser) => (
                          <SelectItem
                            key={jellyfinUser.id}
                            value={jellyfinUser.id.toString()}
                          >
                            {jellyfinUser.name}
                            {jellyfinUser.is_administrator ? " (Admin)" : ""}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  </div>
                ))}
              </div>
            </ScrollArea>
          </TabsContent>
        </Tabs>
        <DialogFooter>
          <Button
            variant="outline"
            onClick={() => setOpen(false)}
            disabled={isLoading}
          >
            Cancel
          </Button>
          <Button onClick={handleSubmit} disabled={isLoading}>
            {isLoading ? "Importing..." : "Start Import"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
