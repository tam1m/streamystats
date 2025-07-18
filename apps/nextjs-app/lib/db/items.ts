import {
  db,
  sessions,
  items,
  users,
  Item,
  Session,
  User,
} from "@streamystats/database";
import {
  and,
  eq,
  desc,
  count,
  sum,
  sql,
  isNotNull,
  gte,
  lte,
  asc,
} from "drizzle-orm";

export interface ItemStats {
  total_views: number;
  total_watch_time: number;
  completion_rate: number;
  first_watched: Date | null;
  last_watched: Date | null;
  users_watched: ItemUserStats[];
  watch_history: ItemWatchHistory[];
  watch_count_by_month: ItemWatchCountByMonth[];
}

export interface ItemUserStats {
  user: User;
  watch_count: number;
  total_watch_time: number;
  completion_rate: number;
  first_watched: Date | null;
  last_watched: Date | null;
}

export interface ItemWatchHistory {
  session: Session;
  user: User | null;
  watch_date: Date;
  watch_duration: number;
  completion_percentage: number;
  play_method: string | null;
  device_name: string | null;
  client_name: string | null;
}

export interface ItemWatchCountByMonth {
  month: string;
  year: number;
  watch_count: number;
  unique_users: number;
  total_watch_time: number;
}

export interface ItemDetailsResponse {
  item: Item;
  total_views: number;
  total_watch_time: number;
  completion_rate: number;
  first_watched: Date | null;
  last_watched: Date | null;
  users_watched: ItemUserStats[];
  watch_history: ItemWatchHistory[];
  watch_count_by_month: ItemWatchCountByMonth[];
}

/**
 * Get comprehensive item details with statistics
 */
export const getItemDetails = async (
  serverId: number,
  itemId: string,
  isAdmin: boolean = false
): Promise<ItemDetailsResponse | null> => {
  // Get the item first
  const item = await db.query.items.findFirst({
    where: and(eq(items.id, itemId), eq(items.serverId, serverId)),
  });

  if (!item) {
    return null;
  }

  // Get basic stats
  const totalStats = await getItemTotalStats(serverId, itemId);
  const watchDates = await getItemWatchDates(serverId, itemId);
  const completionRate = await getItemCompletionRate(serverId, itemId);
  const usersWatched = await getItemUserStats(serverId, itemId, isAdmin);
  const watchHistory = await getItemWatchHistory(serverId, itemId, isAdmin);
  const watchCountByMonth = await getItemWatchCountByMonth(serverId, itemId);

  return {
    item,
    total_views: totalStats.total_views,
    total_watch_time: totalStats.total_watch_time,
    completion_rate: Math.round(completionRate * 10) / 10, // Round to 1 decimal place
    first_watched: watchDates.first_watched,
    last_watched: watchDates.last_watched,
    users_watched: usersWatched,
    watch_history: watchHistory,
    watch_count_by_month: watchCountByMonth,
  };
};

/**
 * Get total views and watch time for an item
 */
export const getItemTotalStats = async (
  serverId: number,
  itemId: string
): Promise<{ total_views: number; total_watch_time: number }> => {
  const result = await db
    .select({
      total_views: count(sessions.id),
      total_watch_time: sum(sessions.playDuration),
    })
    .from(sessions)
    .where(
      and(
        eq(sessions.serverId, serverId),
        eq(sessions.itemId, itemId),
        isNotNull(sessions.playDuration)
      )
    );

  return {
    total_views: result[0]?.total_views || 0,
    total_watch_time: Number(result[0]?.total_watch_time || 0),
  };
};

/**
 * Get first and last watched dates for an item
 */
export const getItemWatchDates = async (
  serverId: number,
  itemId: string
): Promise<{ first_watched: Date | null; last_watched: Date | null }> => {
  const result = await db
    .select({
      first_watched: sql<Date>`MIN(${sessions.startTime})`,
      last_watched: sql<Date>`MAX(${sessions.startTime})`,
    })
    .from(sessions)
    .where(
      and(
        eq(sessions.serverId, serverId),
        eq(sessions.itemId, itemId),
        isNotNull(sessions.startTime)
      )
    );

  return {
    first_watched: result[0]?.first_watched || null,
    last_watched: result[0]?.last_watched || null,
  };
};

/**
 * Get completion rate for an item
 */
export const getItemCompletionRate = async (
  serverId: number,
  itemId: string
): Promise<number> => {
  const result = await db
    .select({
      avg_completion: sql<number>`AVG(${sessions.percentComplete})`,
    })
    .from(sessions)
    .where(
      and(
        eq(sessions.serverId, serverId),
        eq(sessions.itemId, itemId),
        isNotNull(sessions.percentComplete)
      )
    );

  return Number(result[0]?.avg_completion || 0);
};

/**
 * Get user statistics for an item
 */
export const getItemUserStats = async (
  serverId: number,
  itemId: string,
  isAdmin: boolean = false
): Promise<ItemUserStats[]> => {
  const userStats = await db
    .select({
      userId: sessions.userId,
      watch_count: count(sessions.id),
      total_watch_time: sum(sessions.playDuration),
      completion_rate: sql<number>`AVG(${sessions.percentComplete})`,
      first_watched: sql<Date>`MIN(${sessions.startTime})`,
      last_watched: sql<Date>`MAX(${sessions.startTime})`,
    })
    .from(sessions)
    .where(
      and(
        eq(sessions.serverId, serverId),
        eq(sessions.itemId, itemId),
        isNotNull(sessions.userId)
      )
    )
    .groupBy(sessions.userId)
    .orderBy(desc(count(sessions.id)));

  // If not admin, limit to top 10 users
  const limitedStats = isAdmin ? userStats : userStats.slice(0, 10);

  // Get user details for each user
  const result = await Promise.all(
    limitedStats.map(async (stat) => {
      const user = await db.query.users.findFirst({
        where: eq(users.id, stat.userId!),
      });

      return {
        user: user!,
        watch_count: stat.watch_count,
        total_watch_time: Number(stat.total_watch_time || 0),
        completion_rate:
          Math.round((Number(stat.completion_rate) || 0) * 10) / 10,
        first_watched: stat.first_watched,
        last_watched: stat.last_watched,
      };
    })
  );

  return result.filter((item) => item.user); // Filter out items where user wasn't found
};

/**
 * Get watch history for an item
 */
export const getItemWatchHistory = async (
  serverId: number,
  itemId: string,
  isAdmin: boolean = false,
  limit: number = 50
): Promise<ItemWatchHistory[]> => {
  const actualLimit = isAdmin ? limit : Math.min(limit, 25); // Limit for non-admin users

  const sessionData = await db
    .select()
    .from(sessions)
    .leftJoin(users, eq(sessions.userId, users.id))
    .where(
      and(
        eq(sessions.serverId, serverId),
        eq(sessions.itemId, itemId),
        isNotNull(sessions.startTime)
      )
    )
    .orderBy(desc(sessions.startTime))
    .limit(actualLimit);

  return sessionData.map((row) => ({
    session: row.sessions,
    user: row.users,
    watch_date: row.sessions.startTime!,
    watch_duration: row.sessions.playDuration || 0,
    completion_percentage: row.sessions.percentComplete || 0,
    play_method: row.sessions.playMethod,
    device_name: row.sessions.deviceName,
    client_name: row.sessions.clientName,
  }));
};

/**
 * Get watch count by month for an item
 */
export const getItemWatchCountByMonth = async (
  serverId: number,
  itemId: string
): Promise<ItemWatchCountByMonth[]> => {
  const result = await db
    .select({
      month: sql<string>`TO_CHAR(${sessions.startTime}, 'MM')`,
      year: sql<number>`EXTRACT(YEAR FROM ${sessions.startTime})`,
      watch_count: count(sessions.id),
      unique_users: sql<number>`COUNT(DISTINCT ${sessions.userId})`,
      total_watch_time: sum(sessions.playDuration),
    })
    .from(sessions)
    .where(
      and(
        eq(sessions.serverId, serverId),
        eq(sessions.itemId, itemId),
        isNotNull(sessions.startTime)
      )
    )
    .groupBy(
      sql`TO_CHAR(${sessions.startTime}, 'MM')`,
      sql`EXTRACT(YEAR FROM ${sessions.startTime})`
    )
    .orderBy(
      sql`EXTRACT(YEAR FROM ${sessions.startTime})`,
      sql`TO_CHAR(${sessions.startTime}, 'MM')`
    );

  return result.map((row) => ({
    month: row.month,
    year: row.year,
    watch_count: row.watch_count,
    unique_users: row.unique_users,
    total_watch_time: Number(row.total_watch_time || 0),
  }));
};
