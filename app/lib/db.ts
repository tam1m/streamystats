"use server";

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
};

export const createServer = async (
  url: string,
  api_key: string,
  admin_id: string,
  name: string
) => {
  await fetch("http://localhost:4000/api/servers", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      name,
      url,
      api_key,
      admin_id,
    }),
  });
};

export const getServers = async (): Promise<Server[]> => {
  try {
    const res = await fetch("http://localhost:4000/api/servers", {
      cache: "no-store",
    });

    console.log(res);

    if (!res.ok) {
      return [];
    }

    const data = await res.json();
    console.log("data", data);
    return data.data;
  } catch (e) {
    return [];
  }
};

export const getServer = async (): Promise<Server | null> => {
  const servers = await getServers();
  return servers?.[0] || null;
};

export const getUsers = async (serverId: number): Promise<User[]> => {
  const res = await fetch(
    "http://localhost:4000/api/servers/" + serverId + "/users",
    {
      cache: "no-store",
    }
  );

  if (!res.ok) {
    throw new Error("Failed to fetch data");
  }

  const data = await res.json();
  return data.data;
};

export const getUser = async (
  name: string,
  serverId: number
): Promise<User> => {
  const res = await fetch(
    "http://localhost:4000/api/servers/" + serverId + "/users/" + name,
    {
      cache: "no-store",
    }
  );

  if (!res.ok) {
    throw new Error("Failed to fetch data");
  }

  const data = await res.json();
  return data.data;
};

export const getStatistics = async (
  serverId: number
): Promise<Statistics | null> => {
  try {
    const res = await fetch(
      "http://localhost:4000/api/servers/" + serverId + "/statistics",
      {
        cache: "no-store",
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
    "http://localhost:4000/api/servers/" + serverId + "/statistics/history",
    {
      cache: "no-store",
    }
  );

  if (!res.ok) {
    return [];
  }

  const data = await res.json();
  return data.data;
};

const executeSyncTask = async (
  serverId: number,
  endpoint: string
): Promise<void> => {
  const res = await fetch(
    `http://localhost:4000/api/servers/${serverId}/sync${endpoint}`,
    {
      method: "POST",
    }
  );

  console.log(res.status, res.statusText);

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
