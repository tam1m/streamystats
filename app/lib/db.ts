"use server";

import { cookies, headers } from "next/headers";

export type Server = {
  id: number;
  name: string;
  url: string;
  admin_id: string;
  api_key: string;
};

export type Statistics = {
  most_watched_item: {
    item_id: string;
    item_name: string;
    item_type: "Episode" | "Movie";
    total_play_count: number;
    total_play_duration: number; // in seconds
  } | null;
  watchtime_per_day: [
    {
      date: string;
      total_duration: number; // in seconds
    }
  ];
  average_watchtime_per_week_day: {
    day_of_week: number;
    average_duration: number;
  }[];
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

export type User = {
  id: string;
  name: string | null;
  jellyfin_id: string | null;
  watch_stats: { total_watch_time: number; total_plays: number };
  watch_history: any[];
  watch_time_per_day: { date: string; watch_time: number }[];
  is_administrator: boolean;
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

  const res = await fetch(`${process.env.API_URL}/servers/${serverId}`, {
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

export const logout = async (): Promise<void> => {
  cookies().delete("streamystats-token");
  cookies().delete("streamystats-user");
};

export const getToken = async (): Promise<string | undefined> => {
  const cookieStore = cookies();
  const token = cookieStore.get("streamystats-token");
  return token?.value;
};

type UserMe = {
  id: string;
  name: string;
  serverId: number;
};

export const getMe = async (): Promise<UserMe | null> => {
  const cookieStore = cookies();
  const userStr = cookieStore.get("streamystats-user");
  const user = userStr?.value ? JSON.parse(userStr.value) : undefined;

  return user ? (user as UserMe) : null;
};

export type SyncTask = {
  id: number;
  server_id: number;
  sync_type: "partial_sync" | "full_sync";
  status: "completed" | "failed";
  sync_started_at: string; // native datetime
  sync_completed_at: string; // native datetime
};

export const getSyncTasks = async (serverId: number): Promise<SyncTask[]> => {
  return fetch(process.env.API_URL + "/servers/" + serverId + "/sync/tasks", {
    cache: "no-store",
    headers: {
      Authorization: `Bearer ${await getToken()}`,
      "Content-Type": "application/json",
    },
  })
    .then((res) => res.json())
    .then((data) => data.data);
};

export const getSyncTask = async (serverId: number, taskId: number) => {
  return fetch(
    process.env.API_URL + "/servers/" + serverId + "/sync/tasks/" + taskId,
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
    `${process.env.API_URL}/servers/${serverId}/sync${endpoint}`,
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

export const syncPlaybackStatisticsTask = (serverId: number): Promise<void> => {
  return executeSyncTask(serverId, "/playback-statistics");
};
