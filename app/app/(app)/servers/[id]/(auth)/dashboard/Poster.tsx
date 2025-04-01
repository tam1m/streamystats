import { MostWatchedItem, Server } from "@/lib/db";
import Image from "next/image";

export const Poster = ({
  item,
  server,
}: {
  item: MostWatchedItem;
  server: Server;
}) => {
  const getImageUrl = (item: MostWatchedItem) => {
    // For movies, use the item's primary image tag
    if (item.type === "Movie" && item.jellyfin_id && item.primary_image_tag) {
      return `${server.url}/Items/${item.jellyfin_id}/Images/Primary?fillHeight=552&fillWidth=368&quality=96&tag=${item.primary_image_tag}`;
    }

    // For episodes, try to use the series image if available
    if (
      item.type === "Episode" &&
      item.series_id &&
      item.series_primary_image_tag
    ) {
      return `${server.url}/Items/${item.series_id}/Images/Primary?fillHeight=552&fillWidth=368&quality=96&tag=${item.series_primary_image_tag}`;
    }

    // Fallback to a placeholder image
    return null;
  };

  const imageUrl = getImageUrl(item);

  if (!imageUrl) return null;

  return (
    <div className="relative w-full pt-[150%]">
      <Image
        src={imageUrl}
        alt={item.name}
        fill
        className="object-cover"
        sizes="(max-width: 768px) 100vw, (max-width: 1200px) 50vw, 33vw"
      />
    </div>
  );
};
