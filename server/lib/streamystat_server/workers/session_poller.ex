defmodule StreamystatServer.Workers.SessionPoller do
  use GenServer
  require Logger
  alias StreamystatServer.Servers.Models.Server
  alias StreamystatServer.Contexts.PlaybackSessions
  alias StreamystatServer.Repo
  import Ecto.Query, warn: false

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    schedule_polling(30_000)
    {:ok, %{tracked_sessions: %{}}}
  end

  def handle_info(:poll_sessions, state) do
    servers = list_servers()
    updated_state = poll_all_servers(servers, state)
    schedule_polling(30_000)
    {:noreply, updated_state}
  end

  defp list_servers do
    Repo.all(Server)
  end

  defp poll_all_servers(servers, state) do
    Enum.reduce(servers, state, fn server, acc_state ->
      poll_server(server, acc_state)
    end)
  end

  defp poll_server(server, state) do
    case fetch_jellyfin_sessions(server) do
      {:ok, current_sessions} ->
        process_sessions(server, current_sessions, state)

      {:error, reason} ->
        Logger.error("Failed to fetch sessions for server #{server.id}: #{inspect(reason)}")
        state
    end
  end

  defp fetch_jellyfin_sessions(server) do
    url = "#{server.url}/Sessions"

    headers = [
      {"X-MediaBrowser-Token", server.api_key},
      {"Content-Type", "application/json"}
    ]

    case HTTPoison.get(url, headers) do
      {:ok, %{status_code: 200, body: body}} ->
        {:ok, Jason.decode!(body)}

      {:ok, response} ->
        {:error, "Unexpected response: #{inspect(response)}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Processes all current sessions for a server, handling new, updated, and ended sessions.
  # Tracks session state changes and manages the lifecycle of playback sessions.
  defp process_sessions(server, current_sessions, state) do
    server_key = "server_#{server.id}"
    tracked_sessions = Map.get(state.tracked_sessions, server_key, %{})

    filtered_sessions = filter_valid_sessions(current_sessions)

    Logger.debug("Server #{server.id}: #{length(filtered_sessions)} active sessions")

    {new_sessions, updated_sessions, ended_sessions} =
      detect_session_changes(
        filtered_sessions,
        tracked_sessions
      )

    new_tracked_sessions = handle_new_sessions(server, new_sessions)

    merged_sessions = Map.merge(tracked_sessions, new_tracked_sessions)

    updated_tracked_sessions =
      handle_updated_sessions(
        server,
        updated_sessions,
        merged_sessions
      )

    final_tracked_sessions =
      handle_ended_sessions(
        server,
        ended_sessions,
        updated_tracked_sessions
      )

    %{
      state
      | tracked_sessions: Map.put(state.tracked_sessions, server_key, final_tracked_sessions)
    }
  end

  # Filters out invalid sessions like trailers and pre-roll videos.
  # Only returns sessions with valid NowPlayingItem data.
  defp filter_valid_sessions(sessions) do
    Enum.filter(sessions, fn session ->
      case session do
        %{"NowPlayingItem" => item} when not is_nil(item) ->
          item_type = Map.get(item, "Type")
          provider_ids = Map.get(item, "ProviderIds", %{})
          item_type != "Trailer" && !Map.has_key?(provider_ids, "prerolls.video")

        _ ->
          false
      end
    end)
  end

  # Identifies which sessions are new, updated, or ended by comparing current sessions
  # against previously tracked sessions.
  defp detect_session_changes(current_sessions, tracked_sessions) do
    current_map = sessions_to_map(current_sessions)

    new_sessions =
      Enum.filter(current_sessions, fn session ->
        session_key = generate_session_key(session)
        !Map.has_key?(tracked_sessions, session_key)
      end)

    updated_sessions =
      Enum.filter(current_sessions, fn session ->
        session_key = generate_session_key(session)
        Map.has_key?(tracked_sessions, session_key)
      end)

    ended_sessions =
      Enum.filter(Map.keys(tracked_sessions), fn key ->
        !Map.has_key?(current_map, key)
      end)
      |> Enum.map(fn key -> {key, Map.get(tracked_sessions, key)} end)

    {new_sessions, updated_sessions, ended_sessions}
  end

  # Generates a unique key for each session based on user ID, device ID, and content IDs.
  # Handles both series and standalone content differently.
  defp generate_session_key(session) do
    user_id = Map.get(session, "UserId", "")
    device_id = Map.get(session, "DeviceId", "")

    item = Map.get(session, "NowPlayingItem", %{})
    item_id = Map.get(item, "Id", "")
    series_id = Map.get(item, "SeriesId", "")

    if series_id != "" do
      "#{user_id}|#{device_id}|#{series_id}|#{item_id}"
    else
      "#{user_id}|#{device_id}|#{item_id}"
    end
  end

  # Calculates total playback duration accounting for paused states and activity timestamps.
  # Returns duration in seconds.
  defp calculate_duration(tracked, current_paused, last_activity, last_paused, _current_position) do
    was_paused = tracked.is_paused

    cond do
      was_paused == false && current_paused == true && last_paused != nil ->
        tracked.playback_duration +
          DateTime.diff(last_paused, tracked.last_update_time, :second)

      was_paused == false && current_paused == false ->
        tracked.playback_duration +
          DateTime.diff(last_activity, tracked.last_update_time, :second)

      was_paused == true && current_paused == false ->
        tracked.playback_duration

      true ->
        tracked.playback_duration
    end
  end

  # Handles completed sessions by calculating final statistics and saving playback records.
  # Determines if content was completed based on progress percentage.
  defp handle_ended_sessions(server, ended_sessions, tracked_sessions) do
    now = DateTime.utc_now()

    Enum.reduce(ended_sessions, tracked_sessions, fn {key, tracked}, acc ->
      final_duration =
        if !tracked.is_paused do
          tracked.playback_duration + DateTime.diff(now, tracked.last_update_time, :second)
        else
          tracked.playback_duration
        end

      if final_duration > 1 do
        percent_complete =
          if tracked.runtime_ticks > 0 do
            tracked.position_ticks / tracked.runtime_ticks * 100
          else
            0.0
          end

        completed = percent_complete > 90.0

        Logger.info(
          "Ended session for server #{server.id}: User: #{tracked.user_name}, " <>
            "Content: #{tracked.now_playing_item_name}, " <>
            "Final duration: #{final_duration}s, " <>
            "Progress: #{Float.round(percent_complete, 1)}%, " <>
            "Completed: #{completed}"
        )

        playback_record = %{
          user_id: tracked.user_id,
          user_name: tracked.user_name,
          client: tracked.client,
          device_id: tracked.device_id,
          device_name: tracked.device_name,
          item_id: tracked.now_playing_item_id,
          item_name: tracked.now_playing_item_name,
          series_id: tracked.series_id,
          series_name: tracked.series_name,
          season_id: tracked.season_id,
          episode_id: tracked.episode_id,
          play_duration: final_duration,
          play_date: tracked.activity_date_inserted,
          play_method: tracked.play_method,
          position_ticks: tracked.position_ticks,
          runtime_ticks: tracked.runtime_ticks,
          percent_complete: percent_complete,
          completed: completed,
          server_id: server.id
        }

        save_playback_record(server, playback_record)
      end

      Map.delete(acc, key)
    end)
  end

  defp sessions_to_map(sessions) do
    Enum.reduce(sessions, %{}, fn session, acc ->
      key = generate_session_key(session)
      Map.put(acc, key, session)
    end)
  end

  defp handle_new_sessions(server, new_sessions) do
    now = DateTime.utc_now()

    tracked =
      Enum.reduce(new_sessions, %{}, fn session, acc ->
        user_id = Map.get(session, "UserId")
        item = Map.get(session, "NowPlayingItem", %{})
        play_state = Map.get(session, "PlayState", %{})

        session_key = generate_session_key(session)

        user_name = Map.get(session, "UserName")
        item_name = Map.get(item, "Name")
        is_paused = Map.get(play_state, "IsPaused") || false
        last_activity = parse_jellyfin_date(Map.get(session, "LastActivityDate"))

        tracking_record = %{
          session_key: session_key,
          user_id: user_id,
          user_name: user_name,
          client: Map.get(session, "Client"),
          device_id: Map.get(session, "DeviceId"),
          device_name: Map.get(session, "DeviceName"),
          now_playing_item_id: Map.get(item, "Id"),
          now_playing_item_name: item_name,
          series_id: Map.get(item, "SeriesId"),
          series_name: Map.get(item, "SeriesName"),
          season_id: Map.get(item, "SeasonId"),
          episode_id: Map.get(item, "Id"),
          position_ticks: Map.get(play_state, "PositionTicks", 0),
          runtime_ticks: Map.get(item, "RunTimeTicks", 0),
          playback_duration: 0,
          activity_date_inserted: now,
          last_activity_date: last_activity,
          last_paused_date: parse_jellyfin_date(Map.get(session, "LastPausedDate")),
          last_update_time: now,
          is_paused: is_paused,
          play_method: Map.get(play_state, "PlayMethod")
        }

        Logger.info(
          "New session for server #{server.id}: User: #{user_name}, Content: #{item_name}, Paused: #{is_paused}, Duration: 0s"
        )

        Map.put(acc, session_key, tracking_record)
      end)

    tracked
  end

  defp parse_jellyfin_date(nil), do: nil

  defp parse_jellyfin_date(date_str) do
    case DateTime.from_iso8601(date_str) do
      {:ok, datetime, _} -> datetime
      _ -> nil
    end
  end

  defp handle_updated_sessions(server, updated_sessions, tracked_sessions) do
    now = DateTime.utc_now()

    Enum.reduce(updated_sessions, tracked_sessions, fn session, acc ->
      session_key = generate_session_key(session)
      tracked = Map.get(acc, session_key)

      play_state = Map.get(session, "PlayState", %{})
      current_paused = Map.get(play_state, "IsPaused") || false
      current_position = Map.get(play_state, "PositionTicks", 0)
      last_activity = parse_jellyfin_date(Map.get(session, "LastActivityDate"))
      last_paused = parse_jellyfin_date(Map.get(session, "LastPausedDate"))

      updated_duration =
        calculate_duration(tracked, current_paused, last_activity, last_paused, current_position)

      pause_state_changed = current_paused != tracked.is_paused

      duration_increased = updated_duration > tracked.playback_duration + 10

      if pause_state_changed || duration_increased do
        Logger.debug(
          "Updated session for server #{server.id}: User: #{tracked.user_name}, " <>
            "Content: #{tracked.now_playing_item_name}, " <>
            "Paused: #{current_paused}, " <>
            "Duration: #{updated_duration}s, " <>
            "Position: #{format_ticks_as_time(current_position)}"
        )
      end

      updated_record = %{
        tracked
        | position_ticks: current_position,
          is_paused: current_paused,
          last_activity_date: last_activity,
          last_paused_date: last_paused,
          last_update_time: now,
          playback_duration: updated_duration
      }

      Map.put(acc, session_key, updated_record)
    end)
  end

  defp save_playback_record(server, record) do
    user =
      PlaybackSessions.get_user_by_jellyfin_id(
        record.user_id,
        server.id
      )

    attrs = %{
      user_jellyfin_id: record.user_id,
      device_id: record.device_id,
      device_name: record.device_name,
      client_name: record.client,
      item_jellyfin_id: record.item_id,
      item_name: record.item_name,
      series_jellyfin_id: record.series_id,
      series_name: record.series_name,
      season_jellyfin_id: record.season_id,
      play_duration: record.play_duration,
      play_method: record.play_method,
      start_time: record.play_date,
      end_time: DateTime.utc_now(),
      position_ticks: record.position_ticks,
      runtime_ticks: record.runtime_ticks,
      percent_complete: record.percent_complete,
      completed: record.completed,
      user_id: user && user.id,
      server_id: server.id
    }

    case PlaybackSessions.create_playback_session(attrs) do
      {:ok, _session} ->
        Logger.info("Successfully saved playback session for server #{server.id}")

      {:error, changeset} ->
        Logger.error("Failed to save playback session: #{inspect(changeset.errors)}")
    end
  end

  defp schedule_polling(interval_ms) do
    Process.send_after(self(), :poll_sessions, interval_ms)
  end

  defp format_ticks_as_time(ticks) when is_integer(ticks) and ticks > 0 do
    total_seconds = div(ticks, 10_000_000)

    hours = div(total_seconds, 3600)
    minutes = div(rem(total_seconds, 3600), 60)
    seconds = rem(total_seconds, 60)

    "#{pad_time(hours)}:#{pad_time(minutes)}:#{pad_time(seconds)}"
  end

  defp format_ticks_as_time(_), do: "00:00:00"

  defp pad_time(time), do: String.pad_leading("#{time}", 2, "0")
end
