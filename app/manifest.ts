import type { MetadataRoute } from "next";

export default function manifest(): MetadataRoute.Manifest {
  return {
    name: "Streamystats",
    short_name: "Streamystats",
    description: "A statistics service for Jellyfin.",
    start_url: "/",
    display: "standalone",
    background_color: "#000",
    theme_color: "#1C4ED8",
    icons: [
      {
        src: "/web-app-manifest-192x192.png",
        sizes: "192x192",
        type: "image/png",
      },
      {
        src: "/web-app-manifest-512x512.png",
        sizes: "512x512",
        type: "image/png",
      },
    ],
  };
}
