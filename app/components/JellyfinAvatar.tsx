import { User } from "@/lib/db";

export default function JellyfinAvatar({
  user,
  serverUrl,
  imageTag = "", // Add optional imageTag prop with default empty string
  quality = 90, // Add optional quality prop with default 90
}: {
  user: User;
  serverUrl: string | undefined | null;
  imageTag?: string;
  quality?: number;
}) {
  const imageUrl = `/Users/${user.jellyfin_id}/Images/Primary?tag=${imageTag}&quality=${quality}`;

  if (serverUrl && user) {
    return (
      <div className="flex items-center space-x-4">
        <img
          width={40}
          height={40}
          src={`${serverUrl}${imageUrl}`}
          alt="Jellyfin Avatar"
          className="w-10 h-10 rounded-full"
        />
      </div>
    );
  }

  return null;
}
