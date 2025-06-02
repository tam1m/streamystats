import { eq } from "drizzle-orm";
import { db, libraries, Server, NewLibrary } from "@streamystats/database";
import { JellyfinClient, JellyfinLibrary } from "../client";
import {
  SyncMetricsTracker,
  SyncResult,
  createSyncResult,
} from "../sync-metrics";
import pMap from "p-map";

export interface LibrarySyncOptions {
  batchSize?: number;
  concurrency?: number;
}

export interface LibrarySyncData {
  librariesProcessed: number;
  librariesInserted: number;
  librariesUpdated: number;
}

export async function syncLibraries(
  server: Server,
  options: LibrarySyncOptions = {}
): Promise<SyncResult<LibrarySyncData>> {
  const { batchSize = 100, concurrency = 5 } = options;

  const metrics = new SyncMetricsTracker();
  const client = JellyfinClient.fromServer(server);
  const errors: string[] = [];

  try {
    console.log(`Starting library sync for server ${server.name}`);

    // Fetch libraries from Jellyfin
    metrics.incrementApiRequests();
    const jellyfinLibraries = await client.getLibraries();
    console.log(`Fetched ${jellyfinLibraries.length} libraries from Jellyfin`);

    // Process libraries in batches with controlled concurrency
    let librariesInserted = 0;
    let librariesUpdated = 0;

    await pMap(
      jellyfinLibraries,
      async (jellyfinLibrary) => {
        try {
          const wasInserted = await processLibrary(
            jellyfinLibrary,
            server.id,
            metrics
          );

          if (wasInserted) {
            librariesInserted++;
            metrics.incrementLibrariesInserted();
          } else {
            librariesUpdated++;
            metrics.incrementLibrariesUpdated();
          }

          metrics.incrementLibrariesProcessed();
        } catch (error) {
          console.error(
            `Error processing library ${jellyfinLibrary.Id}:`,
            error
          );
          metrics.incrementErrors();
          errors.push(
            `Library ${jellyfinLibrary.Id}: ${
              error instanceof Error ? error.message : "Unknown error"
            }`
          );
        }
      },
      { concurrency }
    );

    const finalMetrics = metrics.finish();
    const data: LibrarySyncData = {
      librariesProcessed: finalMetrics.librariesProcessed,
      librariesInserted: finalMetrics.librariesInserted,
      librariesUpdated: finalMetrics.librariesUpdated,
    };

    console.log(`Library sync completed for server ${server.name}:`, data);

    if (errors.length > 0) {
      return createSyncResult("partial", data, finalMetrics, undefined, errors);
    }

    return createSyncResult("success", data, finalMetrics);
  } catch (error) {
    console.error(`Library sync failed for server ${server.name}:`, error);
    const finalMetrics = metrics.finish();
    const errorData: LibrarySyncData = {
      librariesProcessed: finalMetrics.librariesProcessed,
      librariesInserted: finalMetrics.librariesInserted,
      librariesUpdated: finalMetrics.librariesUpdated,
    };
    return createSyncResult(
      "error",
      errorData,
      finalMetrics,
      error instanceof Error ? error.message : "Unknown error"
    );
  }
}

async function processLibrary(
  jellyfinLibrary: JellyfinLibrary,
  serverId: number,
  metrics: SyncMetricsTracker
): Promise<boolean> {
  // Check if library already exists
  const existingLibrary = await db
    .select()
    .from(libraries)
    .where(eq(libraries.id, jellyfinLibrary.Id))
    .limit(1);

  const libraryData: NewLibrary = {
    id: jellyfinLibrary.Id,
    name: jellyfinLibrary.Name,
    type: jellyfinLibrary.CollectionType || jellyfinLibrary.Type || "Unknown",
    serverId,
    updatedAt: new Date(),
  };

  const isNewLibrary = existingLibrary.length === 0;

  // Upsert library (insert or update if exists)
  await db
    .insert(libraries)
    .values(libraryData)
    .onConflictDoUpdate({
      target: libraries.id,
      set: {
        ...libraryData,
        updatedAt: new Date(),
      },
    });

  metrics.incrementDatabaseOperations();
  return isNewLibrary;
}
