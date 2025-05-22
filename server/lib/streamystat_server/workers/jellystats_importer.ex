defmodule StreamystatServer.Workers.JellystatsImporter do
  use GenServer
  require Logger
  alias StreamystatServer.Repo
  alias StreamystatServer.Servers.Models.Server
  alias StreamystatServer.Jellyfin.Models.User
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
  def handle_cast({:import, server_id, json_data}, %{importing: true} = state) do
    Logger.info("Jellystats import already in progress for server_id: #{state.current_server_id}, skipping new request for server_id: #{server_id}")
    {:noreply, state}
  end

  @impl true
  def handle_cast({:import, server_id, json_data}, state) do
    Logger.info("Starting Jellystats import for server_id: #{server_id}")

    Task.start(fn ->
      result = do_import(server_id, json_data)
      GenServer.cast(__MODULE__, {:import_complete, result})
    end)

    {:noreply, %{state | importing: true, current_server_id: server_id}}
  end

  @impl true
  def handle_cast({:import_complete, result}, state) do
    Logger.info("Jellystats import completed for server_id: #{state.current_server_id}, result: #{inspect(result)}")
    {:noreply, %{state | importing: false, current_server_id: nil}}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, _pid, reason}, state) do
    Logger.error("Import task crashed: #{inspect(reason)}")
    {:noreply, %{state | importing: false, current_server_id: nil}}
  end

  # Main import logic
  defp do_import(server_id, json_data) do
    try do
      with {:ok, server} <- find_server(server_id),
           data <- decode_json_data(json_data),
           result <- process_jellystats_data(server, data) do
        result
      else
        {:error, reason} -> {:error, reason}
      end
    rescue
      e ->
        Logger.error("Error during import: #{inspect(e)}")
        {:error, e}
    end
  end

  defp find_server(server_id) do
    case Repo.get(Server, server_id) do
      nil ->
        Logger.error("Server with ID #{server_id} not found")
        {:error, :server_not_found}
      server ->
        Logger.info("Found server: #{server.name} (ID: #{server.id})")
        {:ok, server}
    end
  end

  defp decode_json_data(data) when is_binary(data) do
    case Jason.decode(data) do
      {:ok, decoded} -> normalize_decoded_data(decoded)
      {:error, error} ->
        Logger.error("Failed to decode JSON data: #{inspect(error)}")
        %{"jf_playback_activity" => []}
    end
  end

  defp decode_json_data(data) when is_list(data), do: data
  defp decode_json_data(data) when is_map(data), do: data
  defp decode_json_data(_), do: %{"jf_playback_activity" => []}

  defp normalize_decoded_data(list) when is_list(list), do: list
  defp normalize_decoded_data(map) when is_map(map) do
    if Map.has_key?(map, "jf_playback_activity") do
      map
    else
      %{"jf_playback_activity" => []}
    end
  end
  defp normalize_decoded_data(_), do: %{"jf_playback_activity" => []}

  defp process_jellystats_data(server, data) do
    try do
      # Extract activities from data
      activities = extract_activities(data)
      Logger.info("Found: #{length(activities)} activities")

      # Process activities
      if Enum.empty?(activities) do
        {:ok, 0}
      else
        process_playback_activities_batch(server, activities)
      end
    rescue
      e ->
        Logger.error("Error in process_jellystats_data: #{inspect(e)}")
        {:error, e}
    end
  end

  defp extract_activities(data) do
    data_list = if is_list(data), do: data, else: [data]

    data_list
    |> Enum.flat_map(fn item ->
      activity_data = item["jf_playback_activity"]

      cond do
        is_list(activity_data) -> activity_data
        is_map(activity_data) -> [activity_data]
        true -> []
      end
    end)
    |> Enum.filter(&is_map/1)
    |> Enum.uniq_by(fn item -> item["Id"] end)
  end

  # Process playback activities with batch operations
  defp process_playback_activities_batch(server, activities) when is_list(activities) do
    Logger.info("Processing #{length(activities)} playback activities in batches")

    try do
      # Get existing sessions and handle updates
      existing_map = get_existing_sessions(server.id)

      # Get current Jellyfin activity IDs and mark old sessions as completed
      mark_old_sessions_completed(server.id, activities)

      # Process activities in batches
      process_activities_in_batches(server, activities, existing_map)

      {:ok, length(activities)}
    rescue
      e ->
        Logger.error("Error in process_playback_activities_batch: #{inspect(e)}")
        {:error, e}
    end
  end

  defp process_playback_activities_batch(_, _), do: {:ok, 0}

  defp get_existing_sessions(server_id) do
    from(s in PlaybackSession,
      where: s.server_id == ^server_id,
      select: {s.item_jellyfin_id, s.id}
    )
    |> Repo.all(timeout: @db_timeout)
    |> Map.new()
  end

  defp mark_old_sessions_completed(server_id, activities) do
    # Extract valid item IDs from activities
    current_jellyfin_ids =
      activities
      |> Enum.map(fn activity ->
        activity["NowPlayingItemId"] || activity["ItemId"] || activity["EpisodeId"] || ""
      end)
      |> Enum.reject(&(&1 == ""))
      |> Enum.uniq()

    # Update sessions if we have valid IDs
    unless Enum.empty?(current_jellyfin_ids) do
      try do
        from(s in PlaybackSession,
          where: s.server_id == ^server_id and s.item_jellyfin_id not in ^current_jellyfin_ids
        )
        |> Repo.update_all(set: [completed: true])
      rescue
        _ -> :ok
      end
    end
  end

  defp process_activities_in_batches(server, activities, existing_map) do
    activities
    |> Enum.chunk_every(@batch_size)
    |> Enum.each(fn batch ->
      # Convert activities to attributes and split into insert/update groups
      {to_insert, to_update} = prepare_activities_for_db(batch, server, existing_map)

      # Process inserts and updates
      process_inserts(to_insert)
      process_updates(to_update)
    end)
  end

  defp prepare_activities_for_db(batch, server, existing_map) do
    batch
    |> Enum.map(fn activity ->
      # Create attributes map from activity data
      attrs = create_attrs_from_activity(activity, server.id)

      # Check if this should be an insert or update
      {attrs, Map.get(existing_map, attrs.item_jellyfin_id)}
    end)
    |> Enum.split_with(fn {_, id} -> is_nil(id) end)
  end

  defp create_attrs_from_activity(activity, server_id) do
    # Extract key fields
    # Prioritize EpisodeId when present for episode content
    item_id = if Map.has_key?(activity, "EpisodeId") and activity["EpisodeId"] != nil and activity["EpisodeId"] != "" do
      activity["EpisodeId"]
    else
      activity["NowPlayingItemId"] || activity["ItemId"] || "Unknown"
    end
    item_name = activity["NowPlayingItemName"] || activity["ItemName"] || "Unknown Item"
    user_id = activity["UserId"]
    user_name = activity["UserName"] || "Unknown User"

    # Generate unique ID using UUID conversion to ensure true uniqueness
    # This avoids collisions that can happen with timestamp-based IDs
    new_id = :crypto.strong_rand_bytes(16)
             |> Base.encode16(case: :lower)
             |> binary_part(0, 16)
             |> String.to_integer(16)
             |> rem(9_223_372_036_854_775_807) # Ensure it fits in a bigint

    # Extract play duration
    play_duration = parse_play_duration(activity["PlaybackDuration"])

    # Current timestamp for database fields
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    # Create attributes map
    %{
      id: new_id,
      user_jellyfin_id: user_id,
      item_jellyfin_id: item_id,
      item_name: item_name,
      user_name: user_name,
      device_name: activity["DeviceName"],
      client_name: activity["Client"],
      play_method: activity["PlayMethod"] || "Unknown",
      start_time: parse_datetime(activity["ActivityDateInserted"] || activity["PlayStartTime"]),
      end_time: parse_datetime(activity["PlayEndTime"]),
      play_duration: play_duration,
      completed: play_duration > 0,
      series_name: activity["SeriesName"],
      server_id: server_id,
      inserted_at: now,
      updated_at: now
    }
  end

  defp parse_play_duration(duration) do
    try do
      case duration do
        val when is_binary(val) ->
          case Integer.parse(val) do
            {value, _} -> value
            :error -> 0
          end
        val when is_integer(val) -> val
        _ -> 0
      end
    rescue
      _ -> 0
    end
  end

  defp process_inserts(to_insert) do
    unless Enum.empty?(to_insert) do
      insert_attrs = Enum.map(to_insert, fn {attrs, _} -> attrs end)

      try do
        {inserted, _} = Repo.insert_all(
          PlaybackSession,
          insert_attrs,
          on_conflict: :nothing,
          conflict_target: [:server_id, :user_jellyfin_id, :item_jellyfin_id, :start_time],
          timeout: @db_timeout
        )
        Logger.info("Successfully inserted #{inserted} playback sessions")
      rescue
        e ->
          Logger.error("Error during batch insert: #{inspect(e)}")
          # Try inserting one by one to isolate problem records
          successful = insert_records_individually(insert_attrs)
          Logger.info("Recovered by inserting #{successful} records individually")
      end
    end
  end

  defp insert_records_individually(attrs_list) do
    Enum.reduce(attrs_list, 0, fn attrs, acc ->
      try do
        %PlaybackSession{}
        |> PlaybackSession.changeset(attrs)
        |> Repo.insert(on_conflict: :nothing, timeout: @db_timeout)
        acc + 1
      rescue
        _ -> acc
      end
    end)
  end

  defp process_updates(to_update) do
    update_count = Enum.reduce(to_update, 0, fn {attrs, id}, acc ->
      try do
        result = Repo.transaction(fn ->
          case Repo.get(PlaybackSession, id) do
            nil -> {:error, :not_found}
            session ->
              changeset =
                PlaybackSession.changeset(session, attrs)
                |> Ecto.Changeset.unique_constraint(:item_jellyfin_id, name: "playback_sessions_unique_index")

              case Repo.update(changeset, timeout: @db_timeout) do
                {:ok, _} -> {:ok, session}
                {:error, %Ecto.Changeset{errors: errors}} ->
                  if is_constraint_error?(errors, :unique) do
                    # This is expected, not an error
                    {:ok, :skipped}
                  else
                    # Real error
                    {:error, errors}
                  end
                other_error -> other_error
              end
          end
        end)

        case result do
          {:ok, {:ok, _}} -> acc + 1  # Successfully updated
          {:ok, :skipped} -> acc + 1  # Skipped due to constraints, still count as success
          _ -> acc
        end
      rescue
        _ -> acc
      end
    end)

    if update_count > 0 do
      Logger.info("Successfully processed #{update_count} existing playback sessions")
    end
  end

  # Helper functions
  defp parse_datetime(nil), do: nil
  defp parse_datetime(datetime_str) when is_binary(datetime_str) do
    try do
      case DateTime.from_iso8601(datetime_str) do
        {:ok, datetime, _} -> DateTime.truncate(datetime, :second)
        _ -> nil
      end
    rescue
      _ -> nil
    end
  end
  defp parse_datetime(_), do: nil

  defp is_constraint_error?(errors, type) do
    Enum.any?(errors, fn {_, {_, details}} ->
      case details do
        [constraint: constraint_type, constraint_name: _] -> constraint_type == type
        _ -> false
      end
    end)
  end
end
