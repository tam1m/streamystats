"use server";

import { cookies, headers } from "next/headers";
import { getMe } from "./me";
import { getToken } from "./token";

export type Server = {
  id: number;
  name: string;
  url: string;
  admin_id: string;
  api_key: string;
};

export type SyncTask = {
  id: number;
  server_id: number;
  sync_type: "full_sync";
  status: "completed" | "failed";
  sync_started_at: string; // native datetime
  sync_completed_at: string; // native datetime
};

export type MostWatchedItem = {
  id: number;
  name: string;
  type: "Episode" | "Movie";
  index_number: number | null;
  production_year: number;
  season_name: string | null;
  series_name: string | null;
  total_play_count: number;
  total_play_duration: number;
  jellyfin_id: string;
};
export type Statistics = {
  most_watched_items?: {
    Movie?: MostWatchedItem[];
    Episode?: MostWatchedItem[];
  };
  watchtime_per_day: [
    {
      date: string;
      watchtime_by_type: {
        item_type: string;
        total_duration: number;
      }[];
    }
  ];
  average_watchtime_per_week_day: {
    day_of_week: number;
    average_duration: number;
  }[];
  total_watch_time: number;
};

export type PlaybackActivity = {
  id: number;
  date_created: string;
  rowid: number;
  item_id: string;
  item_type: string | null;
  item_name: string | null;
  user: User;
  client_name: string | null;
  device_name: string | null;
  device_id: string | null;
  play_method: string | null;
  play_duration: number | null;
  play_count: number | null;
  server_id: number;
  inserted_at: string;
  updated_at: string;
};

export type GenreStat = {
  genre: string;
  watch_time: number;
};

export type User = {
  id: string;
  name: string | null;
  jellyfin_id: string | null;
  watch_stats: { total_watch_time: number; total_plays: number };
  watch_history: any[];
  watch_time_per_day: { date: string; total_duration: number }[];
  is_administrator: boolean;
  genre_stats: GenreStat[];
  longest_streak: number; // days
};

export const createServer = async (
  url: string,
  api_key: string
): Promise<Server> => {
  const result = await fetch(process.env.API_URL + "/servers", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      url,
      api_key,
    }),
  });

  if (!result.ok) {
    throw new Error("Failed to create server");
  }

  const data = await result.json();

  return data.data as Server;
};

export const getServers = async (): Promise<Server[]> => {
  try {
    const res = await fetch(process.env.API_URL + "/servers", {
      cache: "no-store",
    });

    if (!res.ok) {
      return [];
    }

    const data = await res.json();
    return data.data;
  } catch (e) {
    return [];
  }
};

export const getServer = async (
  serverId: number | string
): Promise<Server | null> => {
  try {
    const res = await fetch(process.env.API_URL + "/servers/" + serverId, {
      cache: "no-store",
    });

    if (!res.ok) {
      return null;
    }

    const data = await res.json();
    return data.data;
  } catch (e) {
    return null;
  }
};

export const login = async ({
  serverId,
  username,
  password,
}: {
  serverId: number;
  username: string;
  password?: string | null;
}): Promise<void> => {
  const res = await fetch(process.env.API_URL + "/login", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      username,
      password,
      server_id: serverId,
    }),
  });

  if (!res.ok) {
    throw new Error("Failed to login");
  }

  const data = await res.json();
  const token = data.access_token;
  const user = data.user;

  const h = headers();

  const secure = h.get("x-forwarded-proto") === "https";

  const maxAge = 30 * 24 * 60 * 60;

  cookies().set("streamystats-token", token, {
    httpOnly: true,
    sameSite: "lax",
    path: "/",
    maxAge,
    secure,
  });

  cookies().set(
    "streamystats-user",
    JSON.stringify({
      name: user["Name"],
      id: user["Id"],
      serverId,
    }),
    {
      httpOnly: true,
      sameSite: "lax",
      path: "/",
      maxAge,
      secure,
    }
  );
};

export const deleteServer = async (serverId: number): Promise<void> => {
  const me = await getMe();

  if (!me?.name) throw new Error("Unauthorized: No valid user found");

  const user = await getUser(me?.name, serverId);

  if (!user || !user.is_administrator) {
    throw new Error("Unauthorized: Only administrators can delete servers");
  }

  const token = await getToken();

  if (!token) {
    throw new Error("Unauthorized: No valid token found");
  }

  const res = await fetch(`${process.env.API_URL}/admin/servers/${serverId}`, {
    method: "DELETE",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    },
  });

  if (!res.ok) {
    throw new Error("Failed to delete server");
  }
};

export const getUsers = async (serverId: number): Promise<User[]> => {
  const res = await fetch(
    process.env.API_URL + "/servers/" + serverId + "/users",
    {
      cache: "no-store",
      headers: {
        Authorization: `Bearer ${await getToken()}`,
        "Content-Type": "application/json",
      },
    }
  );

  if (!res.ok) {
    return [];
  }

  const data = await res.json();
  return data.data;
};

export const getUser = async (
  name?: string,
  serverId?: number
): Promise<User | null> => {
  if (!name || !serverId) return null;

  const res = await fetch(
    process.env.API_URL + "/servers/" + serverId + "/users/" + name,
    {
      cache: "no-store",
      headers: {
        Authorization: `Bearer ${await getToken()}`,
        "Content-Type": "application/json",
      },
    }
  );

  if (!res.ok) {
    return null;
  }

  const data = await res.json();
  return data.data;
};

export const getStatistics = async (
  serverId: number
): Promise<Statistics | null> => {
  try {
    const res = await fetch(
      process.env.API_URL + "/servers/" + serverId + "/statistics",
      {
        cache: "no-store",
        headers: {
          Authorization: `Bearer ${await getToken()}`,
          "Content-Type": "application/json",
        },
      }
    );
    if (!res.ok) {
      return null;
    }

    const data = await res.json();
    return data.data as Statistics;
  } catch (e) {
    return null;
  }
};

export type LibraryStatistics = {
  movies_count: number;
  episodes_count: number;
  series_count: number;
  libraries_count: number;
  users_count: number;
};

export const getStatisticsLibrary = async (
  serverId: number
): Promise<LibraryStatistics> => {
  const res = await fetch(
    process.env.API_URL + "/servers/" + serverId + "/statistics/library",
    {
      cache: "no-store",
      headers: {
        Authorization: `Bearer ${await getToken()}`,
        "Content-Type": "application/json",
      },
    }
  );

  if (!res.ok) {
    return {
      movies_count: 0,
      episodes_count: 0,
      series_count: 0,
      libraries_count: 0,
      users_count: 0,
    };
  }

  const data = await res.json();
  return data.data;
};

export const getStatisticsHistory = async (
  serverId: number
): Promise<PlaybackActivity[]> => {
  const res = await fetch(
    process.env.API_URL + "/servers/" + serverId + "/statistics/history",
    {
      cache: "no-store",
      headers: {
        Authorization: `Bearer ${await getToken()}`,
        "Content-Type": "application/json",
      },
    }
  );

  if (!res.ok) {
    return [];
  }

  const data = await res.json();
  return data.data;
};

export type ActivityLogEntry = {
  id: number;
  name: string;
  type: string;
  date: string;
  severity: string;
  server_id: number;
  jellyfin_id: number;
  short_overview: string;
  user_id: number;
};

export type ActivitiesResponse = {
  data: ActivityLogEntry[];
  page: number;
  per_page: number;
  total_pages: number;
  total_items: number;
};

export const getActivities = async (
  serverId: number,
  page = 1
): Promise<ActivitiesResponse> => {
  const queryParams = new URLSearchParams({
    page: page.toString(),
  });

  const res = await fetch(
    `${
      process.env.API_URL
    }/admin/servers/${serverId}/activities?${queryParams.toString()}`,
    {
      next: {
        revalidate: 0,
      },
      headers: {
        Authorization: `Bearer ${await getToken()}`,
        "Content-Type": "application/json",
      },
    }
  );

  if (!res.ok) {
    return {
      data: [],
      page: 1,
      per_page: 0,
      total_pages: 1,
      total_items: 0,
    };
  }

  const data = await res.json();
  return data;
};

export type ItemWatchStats = {
  item: {
    id: number;
    name: string;
    type: "Episode" | "Movie";
    production_year: number;
    season_name?: string | null;
    series_name?: string | null;
  };
  item_id: string;
  total_watch_time: number;
  watch_count: number;
};

export const getStatisticsItems = async (
  serverId: number,
  page = 1,
  search?: string
): Promise<ItemWatchStats[]> => {
  const queryParams = new URLSearchParams({
    page: page.toString(),
  });

  if (search) {
    queryParams.append("search", search);
  }

  const res = await fetch(
    `${
      process.env.API_URL
    }/servers/${serverId}/statistics/items?${queryParams.toString()}`,
    {
      cache: "no-store",
      headers: {
        Authorization: `Bearer ${await getToken()}`,
        "Content-Type": "application/json",
      },
    }
  );

  if (!res.ok) {
    return [];
  }

  const data = await res.json();
  return data.data;
};

export const logout = async (): Promise<void> => {
  cookies().delete("streamystats-token");
  cookies().delete("streamystats-user");
};

export const getSyncTasks = async (serverId: number): Promise<SyncTask[]> => {
  return fetch(
    process.env.API_URL + "/admin/servers/" + serverId + "/sync/tasks",
    {
      cache: "no-store",
      headers: {
        Authorization: `Bearer ${await getToken()}`,
        "Content-Type": "application/json",
      },
    }
  )
    .then((res) => res.json())
    .then((data) => data.data);
};

export const getSyncTask = async (serverId: number, taskId: number) => {
  return fetch(
    process.env.API_URL +
      "/admin/servers/" +
      serverId +
      "/sync/tasks/" +
      taskId,
    {
      cache: "no-store",
      headers: {
        Authorization: `Bearer ${await getToken()}`,
        "Content-Type": "application/json",
      },
    }
  ).then((res) => res.json());
};

const executeSyncTask = async (
  serverId: number,
  endpoint: string
): Promise<void> => {
  const res = await fetch(
    `${process.env.API_URL}/admin/servers/${serverId}/sync${endpoint}`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${await getToken()}`,
        "Content-Type": "application/json",
      },
    }
  );

  if (!res.ok) {
    throw new Error("Failed to fetch data");
  }
};

export const syncFullTask = (serverId: number): Promise<void> => {
  return executeSyncTask(serverId, "/full");
};

export const syncPartialTask = (serverId: number): Promise<void> => {
  return executeSyncTask(serverId, "");
};

export const syncUsersTask = (serverId: number): Promise<void> => {
  return executeSyncTask(serverId, "/users");
};

export const syncLibrariesTask = (serverId: number): Promise<void> => {
  return executeSyncTask(serverId, "/libraries");
};
