# server/lib/streamystat_server/jellyfin/session_poller.ex
defmodule StreamystatServer.Jellyfin.SessionPoller do
  use GenServer
  require Logger
  alias StreamystatServer.Servers.Server
  alias StreamystatServer.Repo
  import Ecto.Query, warn: false

  # Client API
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    # Check all servers every 10 seconds
    schedule_polling(10_000)
    {:ok, %{tracked_sessions: %{}}}
  end

  # Server API
  def handle_info(:poll_sessions, state) do
    # Get all servers (assuming all are active)
    servers = list_servers()

    # Update tracked sessions and state based on polling results
    updated_state = poll_all_servers(servers, state)

    # Schedule next polling
    schedule_polling(10_000)
    {:noreply, updated_state}
  end

  # Private functions
  defp list_servers do
    # Fetch all servers from the database (no active filter)
    Repo.all(Server)
  end

  defp poll_all_servers(servers, state) do
    # For each server, fetch and process sessions
    Enum.reduce(servers, state, fn server, acc_state ->
      poll_server(server, acc_state)
    end)
  end

  defp poll_server(server, state) do
    # Fetch current sessions from Jellyfin API
    case fetch_jellyfin_sessions(server) do
      {:ok, current_sessions} ->
        # Process session changes
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

  defp process_sessions(server, current_sessions, state) do
    # Get server-specific tracked sessions
    server_key = "server_#{server.id}"
    tracked_sessions = Map.get(state.tracked_sessions, server_key, %{})

    # Filter valid sessions (with NowPlayingItem and not trailers)
    filtered_sessions = filter_valid_sessions(current_sessions)

    # Log the number of active sessions
    Logger.debug("Server #{server.id}: #{length(filtered_sessions)} active sessions")

    # Process session changes
    {new_sessions, updated_sessions, ended_sessions} =
      detect_session_changes(
        filtered_sessions,
        tracked_sessions
      )

    # Handle new sessions
    new_tracked_sessions = handle_new_sessions(server, new_sessions)

    # Merge the new sessions with existing ones
    merged_sessions = Map.merge(tracked_sessions, new_tracked_sessions)

    # Handle updated sessions
    updated_tracked_sessions =
      handle_updated_sessions(
        server,
        updated_sessions,
        merged_sessions
      )

    # Handle ended sessions
    final_tracked_sessions =
      handle_ended_sessions(
        server,
        ended_sessions,
        updated_tracked_sessions
      )

    # Update state with new tracked sessions for this server
    %{
      state
      | tracked_sessions: Map.put(state.tracked_sessions, server_key, final_tracked_sessions)
    }
  end

  defp filter_valid_sessions(sessions) do
    Enum.filter(sessions, fn session ->
      # Only include sessions with active media that's not a trailer
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

  defp detect_session_changes(current_sessions, tracked_sessions) do
    # Convert lists to maps for easier comparison
    current_map = sessions_to_map(current_sessions)

    # Find new sessions (in current but not in tracked)
    new_sessions =
      Enum.filter(current_sessions, fn session ->
        session_key = generate_session_key(session)
        !Map.has_key?(tracked_sessions, session_key)
      end)

    # Find updated sessions (in both, check for changes)
    updated_sessions =
      Enum.filter(current_sessions, fn session ->
        session_key = generate_session_key(session)
        Map.has_key?(tracked_sessions, session_key)
      end)

    # Find ended sessions (in tracked but not in current)
    ended_sessions =
      Enum.filter(Map.keys(tracked_sessions), fn key ->
        !Map.has_key?(current_map, key)
      end)
      |> Enum.map(fn key -> {key, Map.get(tracked_sessions, key)} end)

    {new_sessions, updated_sessions, ended_sessions}
  end

  defp sessions_to_map(sessions) do
    Enum.reduce(sessions, %{}, fn session, acc ->
      key = generate_session_key(session)
      Map.put(acc, key, session)
    end)
  end

  defp generate_session_key(session) do
    user_id = Map.get(session, "UserId", "")
    device_id = Map.get(session, "DeviceId", "")

    item = Map.get(session, "NowPlayingItem", %{})
    item_id = Map.get(item, "Id", "")
    series_id = Map.get(item, "SeriesId", "")

    # For TV shows, include both series and episode identifiers
    if series_id != "" do
      "#{user_id}|#{device_id}|#{series_id}|#{item_id}"
    else
      "#{user_id}|#{device_id}|#{item_id}"
    end
  end

  defp handle_new_sessions(server, new_sessions) do
    now = DateTime.utc_now()

    # Convert to tracked_sessions map with session_key as key
    tracked =
      Enum.reduce(new_sessions, %{}, fn session, acc ->
        # Extract needed information
        user_id = Map.get(session, "UserId")
        item = Map.get(session, "NowPlayingItem", %{})
        play_state = Map.get(session, "PlayState", %{})

        session_key = generate_session_key(session)

        # Get useful information for logging
        user_name = Map.get(session, "UserName")
        item_name = Map.get(item, "Name")
        is_paused = Map.get(play_state, "IsPaused") || false
        last_activity = parse_jellyfin_date(Map.get(session, "LastActivityDate"))

        # Create a tracking record with initial state
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

        # Log summary of the new session
        Logger.info(
          "New session for server #{server.id}: User: #{user_name}, Content: #{item_name}, Paused: #{is_paused}, Duration: 0s"
        )

        # Add to accumulator
        Map.put(acc, session_key, tracking_record)
      end)

    # Return the tracking map
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

    # Update tracking records for existing sessions
    Enum.reduce(updated_sessions, tracked_sessions, fn session, acc ->
      session_key = generate_session_key(session)
      tracked = Map.get(acc, session_key)

      # Get current session details
      play_state = Map.get(session, "PlayState", %{})
      current_paused = Map.get(play_state, "IsPaused") || false
      current_position = Map.get(play_state, "PositionTicks", 0)
      last_activity = parse_jellyfin_date(Map.get(session, "LastActivityDate"))
      last_paused = parse_jellyfin_date(Map.get(session, "LastPausedDate"))

      # Calculate duration based on current playback state and timestamps
      updated_duration =
        calculate_duration(tracked, current_paused, last_activity, last_paused, current_position)

      # Check if there's a significant change to log
      pause_state_changed = current_paused != tracked.is_paused
      # 10 second threshold
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

      # Update tracked record with new information
      updated_record = %{
        tracked
        | position_ticks: current_position,
          is_paused: current_paused,
          last_activity_date: last_activity,
          last_paused_date: last_paused,
          last_update_time: now,
          playback_duration: updated_duration
      }

      # Update the accumulator with the updated record
      Map.put(acc, session_key, updated_record)
    end)
  end

  defp calculate_duration(tracked, current_paused, last_activity, last_paused, _current_position) do
    was_paused = tracked.is_paused

    cond do
      # If transitioning from playing to paused, count time from last update to last_paused
      was_paused == false && current_paused == true && last_paused != nil ->
        tracked.playback_duration +
          DateTime.diff(last_paused, tracked.last_update_time, :second)

      # If continuing to play, count time from last update to now
      was_paused == false && current_paused == false ->
        tracked.playback_duration +
          DateTime.diff(last_activity, tracked.last_update_time, :second)

      # If transitioning from paused to playing, don't add time
      was_paused == true && current_paused == false ->
        tracked.playback_duration

      # Remained paused, no additional time
      true ->
        tracked.playback_duration
    end
  end

  defp handle_ended_sessions(server, ended_sessions, tracked_sessions) do
    now = DateTime.utc_now()

    # Process and remove ended sessions
    Enum.reduce(ended_sessions, tracked_sessions, fn {key, tracked}, acc ->
      # Calculate final duration
      final_duration =
        if !tracked.is_paused do
          # If not paused when ended, add time since last update
          tracked.playback_duration + DateTime.diff(now, tracked.last_update_time, :second)
        else
          # If paused when ended, use existing duration
          tracked.playback_duration
        end

      # Only process sessions with sufficient duration (e.g., > 1 second)
      if final_duration > 1 do
        # Calculate percent complete
        percent_complete =
          if tracked.runtime_ticks > 0 do
            tracked.position_ticks / tracked.runtime_ticks * 100
          else
            0.0
          end

        # Determine if content was completed (>90% watched)
        completed = percent_complete > 90.0

        # Log ended session information
        Logger.info(
          "Ended session for server #{server.id}: User: #{tracked.user_name}, " <>
            "Content: #{tracked.now_playing_item_name}, " <>
            "Final duration: #{final_duration}s, " <>
            "Progress: #{Float.round(percent_complete, 1)}%, " <>
            "Completed: #{completed}"
        )

        # Prepare playback record for database
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

        # Save the playback record
        save_playback_record(server, playback_record)
      end

      # Remove the ended session from tracking
      Map.delete(acc, key)
    end)
  end

  defp save_playback_record(server, record) do
    # Look up the Jellyfin user in our database
    user =
      StreamystatServer.Contexts.PlaybackSessions.get_user_by_jellyfin_id(
        record.user_id,
        server.id
      )

    # Prepare attributes for the playback session
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

    # Create the playback session record
    case StreamystatServer.Contexts.PlaybackSessions.create_playback_session(attrs) do
      {:ok, _session} ->
        Logger.info("Successfully saved playback session for server #{server.id}")

      {:error, changeset} ->
        Logger.error("Failed to save playback session: #{inspect(changeset.errors)}")
    end
  end

  defp schedule_polling(interval_ms) do
    Process.send_after(self(), :poll_sessions, interval_ms)
  end

  # Helper function to format ticks as a readable time string (HH:MM:SS)
  defp format_ticks_as_time(ticks) when is_integer(ticks) and ticks > 0 do
    # Convert ticks (100-nanosecond units) to seconds
    total_seconds = div(ticks, 10_000_000)

    hours = div(total_seconds, 3600)
    minutes = div(rem(total_seconds, 3600), 60)
    seconds = rem(total_seconds, 60)

    "#{pad_time(hours)}:#{pad_time(minutes)}:#{pad_time(seconds)}"
  end

  defp format_ticks_as_time(_), do: "00:00:00"

  defp pad_time(time), do: String.pad_leading("#{time}", 2, "0")
end
