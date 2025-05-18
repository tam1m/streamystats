defmodule StreamystatServer.Workers.JellystatsImporter do
  use GenServer
  require Logger
  alias StreamystatServer.Repo
  alias StreamystatServer.Servers.Models.Server
  alias StreamystatServer.Jellyfin.Models.User
  alias StreamystatServer.Jellyfin.Models.Library
  alias StreamystatServer.Jellyfin.Models.Item
  alias StreamystatServer.Sessions.Models.PlaybackSession
  import Ecto.Query

  # Batch size for database operations
  @batch_size 50
  # Timeout for DB operations
  @db_timeout 30_000

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def import_data(server_id, json_data) do
    GenServer.cast(__MODULE__, {:import, server_id, json_data})
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    {:ok, %{importing: false, current_server_id: nil}}
  end

  @impl true
  def handle_cast({:import, server_id, json_data}, state) do
    if state.importing do
      Logger.info(
        "Jellystats import already in progress for server_id: #{state.current_server_id}, skipping new request for server_id: #{server_id}"
      )

      {:noreply, state}
    else
      Logger.info("Starting Jellystats import for server_id: #{server_id}")

      # Spawn the import process
      Task.start(fn ->
        result = do_import(server_id, json_data)
        GenServer.cast(__MODULE__, {:import_complete, result})
      end)

      {:noreply, %{state | importing: true, current_server_id: server_id}}
    end
  end

  @impl true
  def handle_cast({:import_complete, result}, state) do
    Logger.info(
      "Jellystats import completed for server_id: #{state.current_server_id}, result: #{inspect(result)}"
    )

    {:noreply, %{state | importing: false, current_server_id: nil}}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, _pid, reason}, state) do
    Logger.error("Import task crashed: #{inspect(reason)}")
    {:noreply, %{state | importing: false, current_server_id: nil}}
  end

  defp do_import(server_id, json_data) do
    Logger.debug("Looking up server with ID: #{server_id}")

    try do
      server = Repo.get(Server, server_id)

      if server do
        Logger.info("Found server: #{server.name} (ID: #{server.id})")

        # Decode the JSON data if it's a string
        data = decode_data(json_data)

        # Process the data sections
        process_jellystats_data(server, data)
      else
        Logger.error("Server with ID #{server_id} not found")
        {:error, :server_not_found}
      end
    rescue
      e ->
        Logger.error("Error during import: #{inspect(e)}")
        Logger.error(Exception.format_stacktrace())
        {:error, e}
    end
  end

  defp decode_data(data) when is_binary(data) do
    case Jason.decode(data) do
      {:ok, decoded} ->
        # Log the structure to help debug
        Logger.debug("Decoded JSON structure: #{inspect(decoded, pretty: true)}")
        decoded

      {:error, error} ->
        Logger.error("Failed to decode JSON data: #{inspect(error)}")
        %{}
    end
  end

  defp decode_data(data) when is_list(data), do: data
  defp decode_data(data) when is_map(data), do: data
  defp decode_data(_), do: %{}

  defp process_jellystats_data(server, data) when is_map(data) do
    # Process each type of data in separate transactions
    try do
      # Get the data from the correct structure
      activities = get_in(data, ["jf_playback_activity"]) || []

      # Process each type of data in separate transactions
      activities_result = process_playback_activities_batch(server, activities)

      # Combine and return results
      %{
        activities: activities_result
      }
    rescue
      e ->
        Logger.error("Error in process_jellystats_data: #{inspect(e)}")
        Logger.error(Exception.format_stacktrace())
        {:error, e}
    end
  end

  defp process_jellystats_data(server, data) do
    try do
      # Get the data from the correct structure
      # Handle both single object and array cases
      data_list = if is_list(data), do: data, else: [data]

      activities =
        data_list
        |> Enum.flat_map(&(&1["jf_playback_activity"] || []))
        |> Enum.uniq_by(& &1["Id"])

      # Log counts for debugging
      Logger.info("Found: #{length(activities)} activities")

      # Process each type of data in separate transactions
      activities_result = process_playback_activities_batch(server, activities)

      # Combine and return results
      %{
        activities: activities_result
      }
    rescue
      e ->
        Logger.error("Error in process_jellystats_data: #{inspect(e)}")
        Logger.error(Exception.format_stacktrace())
        {:error, e}
    end
  end

  # Process playback activities with batch operations
  defp process_playback_activities_batch(server, activities) when is_list(activities) do
    Logger.info("Processing #{length(activities)} playback activities in batches")

    try do
      # Collect all existing jellyfin_ids
      existing_ids_query =
        from(s in PlaybackSession,
          where: s.server_id == ^server.id,
          select: {s.jellyfin_id, s.id}
        )

      existing_map = Repo.all(existing_ids_query, timeout: @db_timeout) |> Map.new()

      # Get current Jellyfin activity IDs
      current_jellyfin_ids = MapSet.new(activities, & &1["Id"])

      # Mark activities that no longer exist as removed
      from(s in PlaybackSession,
        where: s.server_id == ^server.id and s.jellyfin_id not in ^current_jellyfin_ids
      )
      |> Repo.update_all(
        set: [removed_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)]
      )

      # Split activities into chunks
      activities
      |> Enum.chunk_every(@batch_size)
      |> Enum.each(fn batch ->
        # Separate for insert and update
        {to_insert, to_update} =
          batch
          |> Enum.map(fn activity ->
            attrs = %{
              jellyfin_id: activity["Id"],
              user_id: activity["UserId"],
              item_jellyfin_id: activity["ItemId"],
              started_at: parse_datetime(activity["PlayStartTime"]),
              ended_at: parse_datetime(activity["PlayEndTime"]),
              percent_complete: activity["PercentComplete"] || 0,
              server_id: server.id,
              removed_at: nil
            }

            {attrs, Map.get(existing_map, attrs.jellyfin_id)}
          end)
          |> Enum.split_with(fn {_, id} -> is_nil(id) end)

        # Process inserts
        unless Enum.empty?(to_insert) do
          insert_attrs = Enum.map(to_insert, fn {attrs, _} -> attrs end)
          Repo.insert_all(PlaybackSession, insert_attrs, on_conflict: :nothing, timeout: @db_timeout)
        end

        # Process updates one by one using a transaction
        Enum.each(to_update, fn {attrs, id} ->
          Repo.transaction(
            fn ->
              Repo.get(PlaybackSession, id)
              |> PlaybackSession.changeset(attrs)
              |> Repo.update(timeout: @db_timeout)
            end,
            timeout: @db_timeout
          )
        end)
      end)

      {:ok, length(activities)}
    rescue
      e ->
        Logger.error("Error in process_playback_activities_batch: #{inspect(e)}")
        Logger.error(Exception.format_stacktrace())
        {:error, e}
    end
  end

  defp process_playback_activities_batch(_, _), do: {:ok, 0}

  # Helper function to parse datetime strings
  defp parse_datetime(nil), do: nil
  defp parse_datetime(datetime_str) when is_binary(datetime_str) do
    case DateTime.from_iso8601(datetime_str) do
      {:ok, datetime, _} -> datetime
      _ -> nil
    end
  end
  defp parse_datetime(_), do: nil
end
