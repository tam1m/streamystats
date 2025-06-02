import { db } from "@streamystats/database";
import { activities } from "@streamystats/database/schema";
import { eq, count } from "drizzle-orm";

interface PaginationOptions {
  page?: number;
  pageSize?: number;
}

interface PaginatedResult<T> {
  data: T[];
  pagination: {
    page: number;
    pageSize: number;
    total: number;
    totalPages: number;
  };
}

export const getActivities = async (
  serverId: number | string,
  options: PaginationOptions = {}
): Promise<PaginatedResult<typeof activities.$inferSelect>> => {
  const { page = 1, pageSize = 10 } = options;
  const offset = (page - 1) * pageSize;

  // Get the total count
  const [totalResult] = await db
    .select({ count: count() })
    .from(activities)
    .where(eq(activities.serverId, Number(serverId)));

  const total = totalResult.count;
  const totalPages = Math.ceil(total / pageSize);

  // Get the paginated data
  const data = await db
    .select()
    .from(activities)
    .where(eq(activities.serverId, Number(serverId)))
    .limit(pageSize)
    .offset(offset);

  return {
    data,
    pagination: {
      page,
      pageSize,
      total,
      totalPages,
    },
  };
};
