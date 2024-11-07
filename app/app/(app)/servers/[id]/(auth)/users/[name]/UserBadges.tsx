"use client";

import React from "react";
import { Badge } from "@/components/ui/badge";
import { User } from "@/lib/db";

interface UserBadgesProps {
  user: User;
}

const UserBadges: React.FC<UserBadgesProps> = ({ user }) => {
  return (
    <div className="flex flex-col md:flex-row items-center gap-2">
      <Badge className="self-start" variant="secondary">
        ID: {user.id}
      </Badge>
      <Badge
        className="self-start max-w-[90vw] cursor-pointer"
        variant="secondary"
        onClick={() => {
          navigator.clipboard
            .writeText(user.jellyfin_id || "")
            .then(() => {
              alert("Jellyfin ID copied to clipboard!");
            })
            .catch((err) => {
              console.error("Failed to copy: ", err);
            });
        }}
      >
        <p className="truncate">Jellyfin ID: {user.jellyfin_id}</p>
      </Badge>
    </div>
  );
};

export default UserBadges;
