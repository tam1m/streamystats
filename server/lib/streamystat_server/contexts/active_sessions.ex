defmodule StreamystatServer.Contexts.ActiveSessions do
  @moduledoc """
  Context for retrieving currently active playback sessions from SessionPoller.
  """

  alias StreamystatServer.Workers.SessionPoller
  alias StreamystatServer.Jellyfin.Models.User
  alias StreamystatServer.Jellyfin.Models.Item
  alias StreamystatServer.Repo
  import Ecto.Query

  @doc """
  Gets all active sessions for a given server.
  Enriches the session data with user and item information from the database.
  """
  def list_active_sessions(server_id) do
    # Get raw active sessions from the SessionPoller
    raw_sessions = SessionPoller.get_active_sessions(server_id)

    # Enrich sessions with user and item data
    Enum.map(raw_sessions, fn session ->
      enrich_session_data(session, server_id)
    end)
  end

  @doc """
  Gets active sessions for a specific user on a specific server.
  """
  def list_user_active_sessions(server_id, user_jellyfin_id) do
    server_id = parse_server_id(server_id)

    # Get raw active sessions from the SessionPoller
    raw_sessions = SessionPoller.get_active_sessions(server_id)

    # Filter sessions for this specific user
    user_sessions =
      Enum.filter(raw_sessions, fn session ->
        session.user_id == user_jellyfin_id
      end)

    # Enrich sessions with user and item data
    Enum.map(user_sessions, fn session ->
      enrich_session_data(session, server_id)
    end)
  end

  # Helper to parse server_id from string to integer
  defp parse_server_id(server_id) when is_binary(server_id) do
    case Integer.parse(server_id) do
      {id, ""} -> id
      _ -> server_id
    end
  end

  defp parse_server_id(server_id), do: server_id

  # Enriches session data with user and item information from the database
  defp enrich_session_data(session, server_id) do
    user = get_user(session.user_id, server_id)
    item = get_item(session.now_playing_item_id, server_id)

    session
    |> Map.put(:user, format_user(user))
    |> Map.put(:item, format_item(item))
    |> Map.put(:formatted_position, format_ticks_as_time(session.position_ticks))
    |> Map.put(:formatted_runtime, format_ticks_as_time(session.runtime_ticks))
    |> Map.put(
      :progress_percent,
      calculate_progress_percent(session.position_ticks, session.runtime_ticks)
    )
  end

  # Gets user data from database
  defp get_user(user_jellyfin_id, server_id) do
    Repo.one(
      from(u in User,
        where: u.jellyfin_id == ^user_jellyfin_id and u.server_id == ^server_id
      )
    )
  end

  # Gets item data from database
  defp get_item(item_jellyfin_id, server_id) do
    Repo.one(
      from(i in Item,
        where: i.jellyfin_id == ^item_jellyfin_id and i.server_id == ^server_id
      )
    )
  end

  # Formats user data for API response
  defp format_user(nil), do: nil

  defp format_user(user) do
    %{
      name: user.name,
      jellyfin_id: user.jellyfin_id
    }
  end

  # Formats item data for API response
  defp format_item(nil), do: nil

  defp format_item(item) do
    %{
      id: item.id,
      jellyfin_id: item.jellyfin_id,
      name: item.name,
      type: item.type,
      overview: item.overview,
      runtime_ticks: item.runtime_ticks,
      series_name: item.series_name,
      series_id: item.series_id,
      season_name: item.season_name,
      season_id: item.season_id,
      index_number: item.index_number,
      parent_index_number: item.parent_index_number,
      primary_image_tag: item.primary_image_tag
    }
  end

  # Formats ticks as human-readable time (HH:MM:SS)
  defp format_ticks_as_time(ticks) when is_integer(ticks) and ticks > 0 do
    total_seconds = div(ticks, 10_000_000)
    hours = div(total_seconds, 3600)
    minutes = div(rem(total_seconds, 3600), 60)
    seconds = rem(total_seconds, 60)
    "#{pad_time(hours)}:#{pad_time(minutes)}:#{pad_time(seconds)}"
  end

  defp format_ticks_as_time(_), do: "00:00:00"

  defp pad_time(time), do: String.pad_leading("#{time}", 2, "0")

  # Calculates progress percentage
  defp calculate_progress_percent(position_ticks, runtime_ticks)
       when is_integer(position_ticks) and is_integer(runtime_ticks) and runtime_ticks > 0 do
    (position_ticks / runtime_ticks * 100) |> Float.round(1)
  end

  defp calculate_progress_percent(_, _), do: 0.0
end
