"use server";

import {
  Item,
  sessions,
  items,
  hiddenRecommendations,
} from "@streamystats/database/schema";
import { db } from "@streamystats/database";
import {
  and,
  eq,
  sql,
  desc,
  notInArray,
  isNotNull,
  count,
  inArray,
} from "drizzle-orm";
import { cosineDistance } from "drizzle-orm";
import { getMe } from "./users";

const enableDebug = false;

// Debug logging helper - only logs in development or when DEBUG_RECOMMENDATIONS is enabled
const debugLog = (...args: any[]) => {
  if (
    (process.env.NODE_ENV === "development" ||
      process.env.DEBUG_RECOMMENDATIONS === "true") &&
    enableDebug
  ) {
    console.log(...args);
  }
};

export interface SeriesRecommendationItem {
  item: Item;
  similarity: number;
  basedOn: Item[];
}

export const getSimilarSeries = async (
  serverId: string | number,
  userId?: string,
  limit: number = 10
): Promise<SeriesRecommendationItem[]> => {
  try {
    debugLog(
      `\n🚀 Starting series recommendation process for server ${serverId}, user ${
        userId || "anonymous"
      }, limit ${limit}`
    );

    // Convert serverId to number
    const serverIdNum = Number(serverId);

    // Get the user ID to use for recommendations
    let targetUserId = userId;
    if (!targetUserId) {
      const currentUser = await getMe();
      if (currentUser && currentUser.serverId === serverIdNum) {
        targetUserId = currentUser.id;
        debugLog(`🔍 Using current user: ${targetUserId}`);
      } else {
        debugLog(`❌ No valid user found for series recommendations`);
      }
    } else {
      debugLog(`👤 Using provided user: ${targetUserId}`);
    }

    let recommendations: SeriesRecommendationItem[] = [];

    if (targetUserId) {
      // Get user-specific series recommendations
      debugLog(`\n📺 Getting user-specific series recommendations...`);
      recommendations = await getUserSpecificSeriesRecommendations(
        serverIdNum,
        targetUserId,
        limit
      );
      debugLog(
        `✅ Got ${recommendations.length} user-specific series recommendations`
      );
    }

    // If we don't have enough user-specific recommendations, supplement with popular series
    if (recommendations.length < limit) {
      const remainingLimit = limit - recommendations.length;
      debugLog(
        `\n🔥 Need ${remainingLimit} more series recommendations, getting popular series...`
      );
      const popularRecommendations = await getPopularSeriesRecommendations(
        serverIdNum,
        remainingLimit,
        targetUserId
      );
      debugLog(
        `✅ Got ${popularRecommendations.length} popular series recommendations`
      );
      recommendations = [...recommendations, ...popularRecommendations];
    }

    debugLog(
      `\n🎉 Final result: ${recommendations.length} total series recommendations`
    );
    return recommendations;
  } catch (error) {
    debugLog("❌ Error getting similar series:", error);
    return [];
  }
};

async function getUserSpecificSeriesRecommendations(
  serverId: number,
  userId: string,
  limit: number
): Promise<SeriesRecommendationItem[]> {
  debugLog(
    `\n🎯 Starting user-specific series recommendations for user ${userId}, server ${serverId}, limit ${limit}`
  );

  // Get user's watch history for episodes, aggregated by series
  const userSeriesWatchHistory = await db
    .select({
      seriesId: sessions.seriesId,
      totalPlayDuration: sql<number>`SUM(${sessions.playDuration})`.as(
        "totalPlayDuration"
      ),
      episodeCount: sql<number>`COUNT(DISTINCT ${sessions.itemId})`.as(
        "episodeCount"
      ),
      lastWatched: sql<Date>`MAX(${sessions.endTime})`.as("lastWatched"),
    })
    .from(sessions)
    .where(
      and(
        eq(sessions.serverId, serverId),
        eq(sessions.userId, userId),
        isNotNull(sessions.seriesId),
        isNotNull(sessions.playDuration)
      )
    )
    .groupBy(sessions.seriesId)
    .orderBy(sql`MAX(${sessions.endTime}) DESC`);

  debugLog(`📊 Found ${userSeriesWatchHistory.length} series in watch history`);

  if (userSeriesWatchHistory.length === 0) {
    debugLog(
      "❌ No series watch history found, returning empty recommendations"
    );
    return [];
  }

  // Get the actual Series items for these seriesIds
  const seriesIds = userSeriesWatchHistory
    .map((w) => w.seriesId)
    .filter(Boolean) as string[];

  if (seriesIds.length === 0) {
    debugLog("❌ No valid series IDs found, returning empty recommendations");
    return [];
  }

  const watchedSeriesItems = await db
    .select()
    .from(items)
    .where(
      and(
        eq(items.serverId, serverId),
        eq(items.type, "Series"),
        isNotNull(items.embedding),
        inArray(items.id, seriesIds)
      )
    );

  debugLog(
    `📺 Found ${watchedSeriesItems.length} series items with embeddings`
  );

  // Match series with their watch stats
  const watchedSeriesWithStats = watchedSeriesItems
    .map((series) => {
      const stats = userSeriesWatchHistory.find(
        (w) => w.seriesId === series.id
      );
      return stats
        ? {
            series,
            totalPlayDuration: stats.totalPlayDuration,
            episodeCount: stats.episodeCount,
            lastWatched: new Date(stats.lastWatched),
          }
        : null;
    })
    .filter(Boolean)
    .sort((a, b) => b!.lastWatched.getTime() - a!.lastWatched.getTime());

  debugLog(`🎬 Series with watch stats (top 5):`);
  watchedSeriesWithStats.slice(0, 5).forEach((item, index) => {
    debugLog(
      `  ${index + 1}. "${item!.series.name}" - ${
        item!.episodeCount
      } episodes, ${Math.round(
        item!.totalPlayDuration / 60
      )}min total, last watched: ${item!.lastWatched}`
    );
  });

  if (watchedSeriesWithStats.length === 0) {
    debugLog(
      "❌ No series with embeddings found, returning empty recommendations"
    );
    return [];
  }

  // Get hidden recommendations for this user
  let hiddenItems: { itemId: string }[] = [];
  try {
    hiddenItems = await db
      .select({ itemId: hiddenRecommendations.itemId })
      .from(hiddenRecommendations)
      .where(
        and(
          eq(hiddenRecommendations.serverId, serverId),
          eq(hiddenRecommendations.userId, userId)
        )
      );
  } catch (error) {
    debugLog("Error fetching hidden recommendations:", error);
    hiddenItems = [];
  }

  const hiddenItemIds = hiddenItems.map((h) => h.itemId).filter(Boolean);
  const watchedSeriesIds = watchedSeriesWithStats.map((w) => w!.series.id);
  debugLog(`🙈 Found ${hiddenItemIds.length} hidden items`);

  // Use top watched series to create recommendations
  const recommendations: SeriesRecommendationItem[] = [];

  // Prioritize recent watches but include some highly watched series
  const recentWatches = watchedSeriesWithStats.slice(0, 4);
  debugLog(`⏰ Recent series watches (${recentWatches.length}):`);
  recentWatches.forEach((item, index) => {
    debugLog(`  ${index + 1}. "${item!.series.name}"`);
  });

  // Get top watched series ordered by total play duration
  const topWatchedSeries = watchedSeriesWithStats
    .sort((a, b) => b!.totalPlayDuration - a!.totalPlayDuration)
    .slice(0, 6);

  debugLog(`🔥 Top watched series by duration (${topWatchedSeries.length}):`);
  topWatchedSeries.forEach((item, index) => {
    debugLog(
      `  ${index + 1}. "${item!.series.name}" - ${Math.round(
        item!.totalPlayDuration / 60
      )}min total`
    );
  });

  // Combine recent and top watched, remove duplicates, limit to 6
  const recentIds = new Set(recentWatches.map((item) => item!.series.id));
  const additionalTopWatched = topWatchedSeries.filter(
    (item) => !recentIds.has(item!.series.id)
  );

  const baseSeries = [...recentWatches, ...additionalTopWatched].slice(0, 6);
  debugLog(`📺 Final base series for similarity (${baseSeries.length}):`);
  baseSeries.forEach((item, index) => {
    const isRecent = recentIds.has(item!.series.id);
    debugLog(
      `  ${index + 1}. "${item!.series.name}" (${
        isRecent ? "recent" : "top watched"
      })`
    );
  });

  if (baseSeries.length === 0) {
    debugLog("❌ No base series found, returning empty recommendations");
    return [];
  }

  // Get candidate series similar to any of the base series
  const candidateSeries = new Map<
    string,
    { item: Item; similarities: number[]; basedOn: Item[] }
  >();

  for (const watchedSeriesItem of baseSeries) {
    const watchedSeries = watchedSeriesItem!.series;
    if (!watchedSeries.embedding) {
      debugLog(`⚠️ Skipping "${watchedSeries.name}" - no embedding`);
      continue;
    }

    debugLog(`\n🔍 Finding series similar to "${watchedSeries.name}"`);

    // Calculate cosine similarity with other series
    const similarity = sql<number>`1 - (${cosineDistance(
      items.embedding,
      watchedSeries.embedding
    )})`;

    const similarSeries = await db
      .select({
        item: items,
        similarity: similarity,
      })
      .from(items)
      .where(
        and(
          eq(items.serverId, serverId),
          eq(items.type, "Series"),
          isNotNull(items.embedding),
          notInArray(items.id, watchedSeriesIds), // Exclude already watched series
          hiddenItemIds.length > 0
            ? notInArray(items.id, hiddenItemIds)
            : sql`true` // Exclude hidden items
        )
      )
      .orderBy(desc(similarity))
      .limit(20);

    debugLog(`  Found ${similarSeries.length} similar series (top 5):`);
    similarSeries.slice(0, 5).forEach((result, index) => {
      debugLog(
        `    ${index + 1}. "${result.item.name}" - similarity: ${Number(
          result.similarity
        ).toFixed(3)}`
      );
    });

    // Filter for good similarity scores
    const qualifiedSimilarSeries = similarSeries.filter(
      (result) => Number(result.similarity) > 0.6
    );

    debugLog(`  ${qualifiedSimilarSeries.length} series with similarity > 0.6`);

    // Add similarities to candidate series
    for (const result of qualifiedSimilarSeries) {
      const seriesId = result.item.id;
      const simScore = Number(result.similarity);

      if (!candidateSeries.has(seriesId)) {
        candidateSeries.set(seriesId, {
          item: result.item,
          similarities: [],
          basedOn: [],
        });
      }

      const candidate = candidateSeries.get(seriesId)!;
      candidate.similarities.push(simScore);
      candidate.basedOn.push(watchedSeries);
    }
  }

  debugLog(`\n📋 Total unique candidate series: ${candidateSeries.size}`);

  // Calculate final recommendations with weighted similarities
  const finalRecommendations = Array.from(candidateSeries.values())
    .map((candidate) => ({
      item: candidate.item,
      similarity:
        candidate.similarities.reduce((sum, sim) => sum + sim, 0) /
        candidate.similarities.length,
      basedOn: candidate.basedOn.slice(0, 3), // Limit to 3 base series for clarity
    }))
    .sort((a, b) => b.similarity - a.similarity)
    .slice(0, limit);

  debugLog(`\n✅ Final ${finalRecommendations.length} series recommendations:`);
  finalRecommendations.forEach((rec, index) => {
    const baseSeriesNames = rec.basedOn.map((s) => `"${s.name}"`).join(", ");
    const type = rec.basedOn.length >= 2 ? "multi-series" : "single-series";
    debugLog(
      `  ${index + 1}. "${rec.item.name}" (similarity: ${rec.similarity.toFixed(
        3
      )}, ${type}) <- ${baseSeriesNames}`
    );
  });

  return finalRecommendations;
}

async function getPopularSeriesRecommendations(
  serverId: number,
  limit: number,
  excludeUserId?: string
): Promise<SeriesRecommendationItem[]> {
  debugLog(
    `\n🔥 Getting popular series recommendations for server ${serverId}, limit ${limit}, excluding user ${
      excludeUserId || "none"
    }`
  );

  // Get series that are popular (most episodes watched) but exclude series already watched by the current user
  let watchedSeriesIds: string[] = [];
  let hiddenItemIds: string[] = [];

  if (excludeUserId) {
    const userWatchedSeries = await db
      .select({ seriesId: sessions.seriesId })
      .from(sessions)
      .where(
        and(
          eq(sessions.serverId, serverId),
          eq(sessions.userId, excludeUserId),
          isNotNull(sessions.seriesId)
        )
      )
      .groupBy(sessions.seriesId);

    watchedSeriesIds = userWatchedSeries
      .map((w) => w.seriesId)
      .filter((id): id is string => id !== null);

    debugLog(`🚫 Excluding ${watchedSeriesIds.length} already watched series`);

    // Get hidden recommendations for this user
    let hiddenItems: { itemId: string }[] = [];
    try {
      hiddenItems = await db
        .select({ itemId: hiddenRecommendations.itemId })
        .from(hiddenRecommendations)
        .where(
          and(
            eq(hiddenRecommendations.serverId, serverId),
            eq(hiddenRecommendations.userId, excludeUserId)
          )
        );
    } catch (error) {
      debugLog("Error fetching hidden recommendations:", error);
      hiddenItems = [];
    }

    hiddenItemIds = hiddenItems.map((h) => h.itemId).filter(Boolean);
    debugLog(`🙈 Excluding ${hiddenItemIds.length} hidden series`);
  }

  // Get popular series based on episode watch count
  const popularSeriesQuery = db
    .select({
      item: items,
      episodeWatchCount: count(sessions.id).as("episodeWatchCount"),
    })
    .from(items)
    .leftJoin(sessions, eq(items.id, sessions.seriesId))
    .where(
      and(
        eq(items.serverId, serverId),
        eq(items.type, "Series"),
        isNotNull(items.embedding),
        // Exclude user's watched series if we have a user
        watchedSeriesIds.length > 0
          ? notInArray(items.id, watchedSeriesIds)
          : sql`true`,
        // Exclude user's hidden series if we have a user
        hiddenItemIds.length > 0
          ? notInArray(items.id, hiddenItemIds)
          : sql`true`
      )
    )
    .groupBy(items.id)
    .orderBy(desc(count(sessions.id)))
    .limit(limit);

  const popularSeries = await popularSeriesQuery;

  debugLog(`📈 Found ${popularSeries.length} popular series:`);
  popularSeries.slice(0, 5).forEach((item, index) => {
    debugLog(
      `  ${index + 1}. "${item.item.name}" - ${
        item.episodeWatchCount
      } episode watches`
    );
  });
  if (popularSeries.length > 5) {
    debugLog(`  ... and ${popularSeries.length - 5} more`);
  }

  // Transform to recommendation format
  return popularSeries.map((item) => ({
    item: item.item,
    similarity: 0.5, // Default similarity for popular recommendations
    basedOn: [], // No specific series these are based on
  }));
}

export const hideSeriesRecommendation = async (
  serverId: string | number,
  itemId: string
) => {
  try {
    // Get the current user
    const currentUser = await getMe();
    if (!currentUser || currentUser.serverId !== Number(serverId)) {
      return {
        success: false,
        error: "User not found or not authorized for this server",
      };
    }

    const serverIdNum = Number(serverId);

    // Check if the recommendation is already hidden
    const existingHidden = await db
      .select()
      .from(hiddenRecommendations)
      .where(
        and(
          eq(hiddenRecommendations.serverId, serverIdNum),
          eq(hiddenRecommendations.userId, currentUser.id),
          eq(hiddenRecommendations.itemId, itemId)
        )
      )
      .limit(1);

    if (existingHidden.length > 0) {
      return {
        success: true,
        error: false,
        message: "Series recommendation already hidden",
      };
    }

    // Insert the hidden recommendation
    await db.insert(hiddenRecommendations).values({
      serverId: serverIdNum,
      userId: currentUser.id,
      itemId: itemId,
    });

    return {
      success: true,
      error: false,
      message: "Series recommendation hidden successfully",
    };
  } catch (error) {
    debugLog("Error hiding series recommendation:", error);
    return {
      success: false,
      error: error instanceof Error ? error.message : "Unknown error",
    };
  }
};
