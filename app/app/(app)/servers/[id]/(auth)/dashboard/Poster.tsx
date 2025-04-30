"use client";

import { JellyfinSession } from "@/app/api/Sessions/route";
import { Item, Server } from "@/lib/db";
import Image from "next/image";
import { memo, useEffect, useMemo, useState } from "react";
import { Blurhash } from "react-blurhash";
import { Film, Tv } from "lucide-react";

// Define the possible image types that can be requested
export type ImageType = "Primary" | "Backdrop" | "Thumb" | "Logo";

const PosterComponent = ({
  item,
  server,
  width = 500,
  height = 500,
  className = "",
  preferredImageType = "Primary", // New prop to specify preferred image type
  size = "default", // can be "default" (w-16) or "large" (w-24)
}: {
  item: Item;
  server: Server;
  width?: number;
  height?: number;
  className?: string;
  preferredImageType?: ImageType;
  size?: "default" | "large";
}) => {
  const [isLoading, setIsLoading] = useState(true);
  const [hasError, setHasError] = useState(false);
  const [blurHash, setBlurHash] = useState<string | null>(null);

  // Determine if it's an episode to handle parent images
  const isEpisode = useMemo(() => item.type === "Episode", [item.type]);

  // Memoized container class
  const containerClassName = useMemo(
    () => `relative ${size === "large" ? "w-24" : "w-16"} ${className} overflow-hidden rounded-md bg-muted`,
    [className, size],
  );

  const { blurhashX, blurhashY } = useMemo(() => {
    const x = 32;
    let y;

    // Choose aspect ratio based on preferred image type or item type
    if (
      (!isEpisode && preferredImageType === "Primary") ||
      (preferredImageType === "Logo" && item.type === "Movie")
    ) {
      y = Math.round(x * (3 / 2)); // 2:3 aspect ratio for portrait content
    } else if (
      preferredImageType === "Backdrop" ||
      preferredImageType === "Thumb" ||
      item.type === "Episode"
    ) {
      y = Math.round(x * (9 / 16)); // 16:9 aspect ratio for landscape content
    } else {
      y = x; // Fallback to square
    }

    return { blurhashX: x, blurhashY: y };
  }, [item.type, preferredImageType]);

  // Calculate aspect ratio styles based on preferred image type
  const aspectRatioStyle = useMemo(() => {
    if (
      (!isEpisode && preferredImageType === "Primary") ||
      (preferredImageType === "Logo" && item.type === "Movie")
    ) {
      return { aspectRatio: "2/3" }; // movie poster ratio
    } else if (
      preferredImageType === "Backdrop" ||
      preferredImageType === "Thumb" ||
      item.type === "Episode"
    ) {
      return { aspectRatio: "16/9" }; // landscape ratio
    }
    return { aspectRatio: "1/1" }; // square
  }, [item.type, preferredImageType]);

  // Memoize the image URL calculation
  const imageUrl = useMemo(() => {
    if (!item.jellyfin_id) return null;

    // Function to get URL for a specific image type
    const getImageUrlByType = (type: ImageType): string | null => {
      switch (type) {
        case "Primary":
          if (item.primary_image_tag) {
            return `${server.url}/Items/${item.jellyfin_id}/Images/Primary?fillHeight=${height}&fillWidth=${width}&quality=96&tag=${item.primary_image_tag}`;
          } else if (
            isEpisode &&
            item.series_id &&
            item.series_primary_image_tag
          ) {
            return `${server.url}/Items/${item.series_id}/Images/Primary?fillHeight=${height}&fillWidth=${width}&quality=96&tag=${item.series_primary_image_tag}`;
          }
          return null;

        case "Backdrop":
          if (item.backdrop_image_tags && item.backdrop_image_tags.length > 0) {
            return `${server.url}/Items/${item.jellyfin_id}/Images/Backdrop?fillHeight=${height}&fillWidth=${width}&quality=96&tag=${item.backdrop_image_tags[0]}`;
          } else if (
            isEpisode &&
            item.parent_backdrop_item_id &&
            item.parent_backdrop_image_tags &&
            item.parent_backdrop_image_tags.length > 0
          ) {
            return `${server.url}/Items/${item.parent_backdrop_item_id}/Images/Backdrop?fillHeight=${height}&fillWidth=${width}&quality=96&tag=${item.parent_backdrop_image_tags[0]}`;
          }
          return null;

        case "Thumb":
          if (item?.primary_image_thumb_tag) {
            return `${server.url}/Items/${item?.jellyfin_id}/Images/Thumb?fillHeight=${height}&fillWidth=${width}&quality=96&tag=${item?.primary_image_thumb_tag}`;
          } else if (
            isEpisode &&
            item?.parent_thumb_item_id &&
            item?.parent_thumb_image_tag
          ) {
            return `${server.url}/Items/${item?.parent_thumb_item_id}/Images/Thumb?fillHeight=${height}&fillWidth=${width}&quality=96&tag=${item?.parent_thumb_image_tag}`;
          }
          return null;

        case "Logo":
          if (item?.primary_image_logo_tag) {
            return `${server.url}/Items/${item?.jellyfin_id}/Images/Logo?fillHeight=${height}&fillWidth=${width}&quality=96&tag=${item?.primary_image_logo_tag}`;
          }
          return null;

        default:
          return null;
      }
    };

    // Try the preferred image type first
    let url = getImageUrlByType(preferredImageType);

    // If preferred image type doesn't exist, fall back to other types in priority order
    if (!url && preferredImageType !== "Primary")
      url = getImageUrlByType("Primary");
    if (!url && preferredImageType !== "Backdrop")
      url = getImageUrlByType("Backdrop");
    if (!url && preferredImageType !== "Thumb")
      url = getImageUrlByType("Thumb");
    if (!url && preferredImageType !== "Logo") url = getImageUrlByType("Logo");

    return url;
  }, [
    item.jellyfin_id,
    item.primary_image_tag,
    item.backdrop_image_tags,
    item.series_id,
    item.series_primary_image_tag,
    item.parent_backdrop_item_id,
    item.parent_backdrop_image_tags,
    item?.parent_thumb_item_id,
    item?.parent_thumb_image_tag,
    item?.primary_image_logo_tag,
    item?.primary_image_thumb_tag,
    isEpisode,
    server.url,
    height,
    width,
    preferredImageType,
  ]);

  // Get blur hash for loading state
  useEffect(() => {
    if (item.image_blur_hashes) {
      // Try to parse image_blur_hashes if it's a string
      const blurHashes = item.image_blur_hashes;

      // Try to get blur hash for the preferred image type
      if (
        preferredImageType === "Primary" &&
        blurHashes.Primary &&
        item.primary_image_tag
      ) {
        setBlurHash(blurHashes.Primary[item.primary_image_tag]);
      } else if (
        preferredImageType === "Primary" &&
        isEpisode &&
        blurHashes.Primary &&
        item.series_primary_image_tag
      ) {
        setBlurHash(blurHashes.Primary[item.series_primary_image_tag]);
      } else if (
        preferredImageType === "Backdrop" &&
        blurHashes.Backdrop &&
        item.backdrop_image_tags &&
        item.backdrop_image_tags.length > 0
      ) {
        setBlurHash(blurHashes.Backdrop[item.backdrop_image_tags[0]]);
      } else if (
        preferredImageType === "Backdrop" &&
        isEpisode &&
        blurHashes.Backdrop &&
        item.parent_backdrop_image_tags &&
        item.parent_backdrop_image_tags.length > 0
      ) {
        setBlurHash(blurHashes.Backdrop[item.parent_backdrop_image_tags[0]]);
      } else if (
        preferredImageType === "Thumb" &&
        blurHashes.Thumb &&
        item.primary_image_thumb_tag
      ) {
        setBlurHash(blurHashes.Thumb[item.primary_image_thumb_tag]);
      } else if (
        preferredImageType === "Thumb" &&
        isEpisode &&
        blurHashes.Thumb &&
        item.parent_thumb_image_tag
      ) {
        setBlurHash(blurHashes.Thumb[item.parent_thumb_image_tag]);
      } else if (
        preferredImageType === "Logo" &&
        blurHashes.Logo &&
        item.primary_image_logo_tag
      ) {
        setBlurHash(blurHashes.Logo[item.primary_image_logo_tag]);
      }
      // Fallbacks if preferred type's blur hash isn't available
      else if (blurHashes.Primary && item.primary_image_tag) {
        setBlurHash(blurHashes.Primary[item.primary_image_tag]);
      } else if (
        isEpisode &&
        blurHashes.Primary &&
        item.series_primary_image_tag
      ) {
        setBlurHash(blurHashes.Primary[item.series_primary_image_tag]);
      } else if (
        blurHashes.Backdrop &&
        item.backdrop_image_tags &&
        item.backdrop_image_tags.length > 0
      ) {
        setBlurHash(blurHashes.Backdrop[item.backdrop_image_tags[0]]);
      } else if (
        isEpisode &&
        blurHashes.Backdrop &&
        item.parent_backdrop_image_tags &&
        item.parent_backdrop_image_tags.length > 0
      ) {
        setBlurHash(blurHashes.Backdrop[item.parent_backdrop_image_tags[0]]);
      } else if (blurHashes.Thumb && Object.keys(blurHashes.Thumb).length > 0) {
        const thumbTag = Object.keys(blurHashes.Thumb)[0];
        setBlurHash(blurHashes.Thumb[thumbTag]);
      } else if (isEpisode && blurHashes.Thumb && item.parent_thumb_image_tag) {
        setBlurHash(blurHashes.Thumb[item.parent_thumb_image_tag]);
      }
    }
  }, [
    item.image_blur_hashes,
    item.primary_image_tag,
    item.series_primary_image_tag,
    item.backdrop_image_tags,
    item.parent_backdrop_image_tags,
    item.parent_thumb_image_tag,
    item.primary_image_logo_tag,
    item.primary_image_thumb_tag,
    isEpisode,
    preferredImageType,
  ]);

  // Early return if no image or error
  if (!imageUrl || hasError) {
    return (
      <div className={containerClassName} style={aspectRatioStyle}>
        <FallbackPoster type={item.type} />
      </div>
    );
  }

  return (
    <div className={containerClassName} style={aspectRatioStyle}>
      {/* Blur hash placeholder */}
      {blurHash && !hasError && (
        <div className="absolute inset-0 w-full h-full">
          <Blurhash
            hash={blurHash}
            resolutionX={blurhashX}
            resolutionY={blurhashY}
            height="100%"
            width="100%"
            punch={1}
            style={{
              position: "absolute",
              top: 0,
              right: 0,
              bottom: 0,
              left: 0,
              display: "flex",
            }}
          />
        </div>
      )}

      {/* Actual image */}
      <Image
        src={imageUrl}
        alt={item.name || "Media"}
        fill
        className="object-cover rounded-md transition-opacity duration-300"
        style={{
          opacity: isLoading ? 0 : 1,
          position: "absolute",
          top: 0,
          left: 0,
        }}
        sizes="(max-width: 768px) 100vw, (max-width: 1200px) 50vw, 33vw"
        priority={false}
        onLoad={() => setIsLoading(false)}
        onError={() => {
          setIsLoading(false);
          setHasError(true);
        }}
      />
    </div>
  );
};

// Memoize the entire component to prevent unnecessary re-renders
export const Poster = memo(PosterComponent, (prevProps, nextProps) => {
  // Deep comparison of essential item properties
  return (
    prevProps.item.jellyfin_id === nextProps.item.jellyfin_id &&
    prevProps.item.primary_image_tag === nextProps.item.primary_image_tag &&
    prevProps.item.image_blur_hashes === nextProps.item.image_blur_hashes &&
    prevProps.server.url === nextProps.server.url &&
    prevProps.width === nextProps.width &&
    prevProps.height === nextProps.height &&
    prevProps.className === nextProps.className &&
    prevProps.preferredImageType === nextProps.preferredImageType &&
    prevProps.size === nextProps.size
  );
});

function FallbackPoster({ type }: { type: string }) {
  return (
    <div className="w-full h-full bg-muted flex flex-col items-center justify-center rounded-md" style={{ aspectRatio: "2/3" }}>
      <div className="flex flex-col items-center gap-1">
        {type === "Movie" ? (
          <Film className="h-4 w-4 text-muted-foreground/70" />
        ) : (
          <Tv className="h-4 w-4 text-muted-foreground/70" />
        )}
        <span className="text-[10px] text-muted-foreground/70">Archived</span>
      </div>
    </div>
  );
}
