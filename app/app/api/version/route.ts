import type { NextApiRequest, NextApiResponse } from "next";
import { NextRequest, NextResponse } from "next/server";

type VersionResponse = {
  currentVersion: string;
  latestVersion: string;
  hasUpdate: boolean;
  buildTime?: number;
};

export async function GET(
  req: NextRequest,
  res: NextResponse<VersionResponse>
) {
  const currentVersion = process.env.NEXT_PUBLIC_VERSION || "edge";
  const buildTime = Number.parseInt(
    process.env.NEXT_PUBLIC_BUILD_TIME || "0",
    10
  );

  try {
    // Get latest version from GitHub API
    let latestVersion = "edge";
    let latestCommitSha = "";

    // Check for latest release version
    const releasesResponse = await fetch(
      "https://api.github.com/repos/fredrikburmester/streamystats/releases/latest",
      {
        headers: {
          Accept: "application/vnd.github.v3+json",
        },
      }
    );

    if (releasesResponse.ok) {
      const releaseData = await releasesResponse.json();
      latestVersion = releaseData.tag_name || "edge";
    }

    // If user is on edge, check for latest commit to main
    if (currentVersion === "edge") {
      const commitsResponse = await fetch(
        "https://api.github.com/repos/fredrikburmester/streamystats/commits/main",
        {
          headers: {
            Accept: "application/vnd.github.v3+json",
          },
        }
      );

      if (commitsResponse.ok) {
        const commitData = await commitsResponse.json();
        latestCommitSha = commitData.sha.substring(0, 7);
      }
    }

    // Determine if there's an update
    let hasUpdate = false;

    if (currentVersion === "edge" && latestCommitSha) {
      // For edge builds, check if there's a new commit
      // We compare if the current version contains the commit SHA (as it might be 'edge-abc123')
      hasUpdate = !currentVersion.includes(latestCommitSha);
    } else if (currentVersion !== latestVersion && latestVersion !== "edge") {
      // For version tags, compare semantic versions
      hasUpdate = compareVersions(currentVersion, latestVersion) < 0;
    }

    console.log({
      currentVersion,
      latestCommitSha,
      latestVersion,
      hasUpdate,
      buildTime,
    });

    if (res.status === 200) {
      return new Response(
        JSON.stringify({
          currentVersion,
          latestVersion:
            currentVersion === "edge" ? latestCommitSha : latestVersion,
          hasUpdate,
          buildTime,
        }),
        {
          headers: {
            "Content-Type": "application/json",
          },
        }
      );
    }
  } catch (error) {
    console.error("Error checking for updates:", error);
  }

  return new Response(
    JSON.stringify({
      currentVersion,
      latestVersion: currentVersion,
      hasUpdate: false,
      buildTime,
    }),
    {
      headers: {
        "Content-Type": "application/json",
      },
    }
  );
}

// Simple semantic version comparator
function compareVersions(a: string, b: string): number {
  if (a === "edge") return -1;
  if (b === "edge") return 1;

  // Remove 'v' prefix if present
  const versionA = a.startsWith("v") ? a.substring(1) : a;
  const versionB = b.startsWith("v") ? b.substring(1) : b;

  const partsA = versionA.split(".").map(Number);
  const partsB = versionB.split(".").map(Number);

  for (let i = 0; i < Math.max(partsA.length, partsB.length); i++) {
    const partA = i < partsA.length ? partsA[i] : 0;
    const partB = i < partsB.length ? partsB[i] : 0;

    if (partA !== partB) {
      return partA - partB;
    }
  }

  return 0;
}
