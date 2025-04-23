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
      # libraries = get_in(data, ["jf_libraries"]) || []
      # users = get_in(data, ["jf_users"]) || []
      # items = get_in(data, ["jf_library_items"]) || []
      activities = get_in(data, ["jf_playback_activity"]) || []

      # Process each type of data in separate transactions
      # libraries_result = process_libraries_batch(server, libraries)
      # users_result = process_users_batch(server, users)
      # items_result = process_items_batch(server, items)
      activities_result = process_playback_activities_batch(server, activities)

      # Combine and return results
      %{
        # libraries: libraries_result,
        # users: users_result,
        # items: items_result,
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

      # libraries =
      #   data_list
      #   |> Enum.flat_map(& &1["jf_libraries"] || [])
      #   |> Enum.uniq_by(& &1["Id"])

      # users =
      #   data_list
      #   |> Enum.flat_map(& &1["jf_users"] || [])
      #   |> Enum.uniq_by(& &1["Id"])

      # items =
      #   data_list
      #   |> Enum.flat_map(& &1["jf_library_items"] || [])
      #   |> Enum.uniq_by(& &1["Id"])

      activities =
        data_list
        |> Enum.flat_map(&(&1["jf_playback_activity"] || []))
        |> Enum.uniq_by(& &1["Id"])

      # Log counts for debugging
      Logger.info("Found: #{length(activities)} activities")

      # Process each type of data in separate transactions
      # libraries_result = process_libraries_batch(server, libraries)
      # users_result = process_users_batch(server, users)
      # items_result = process_items_batch(server, items)
      activities_result = process_playback_activities_batch(server, activities)

      # Combine and return results
      %{
        # libraries: libraries_result,
        # users: users_result,
        # items: items_result,
        activities: activities_result
      }
    rescue
      e ->
        Logger.error("Error in process_jellystats_data: #{inspect(e)}")
        Logger.error(Exception.format_stacktrace())
        {:error, e}
    end
  end

  # Process libraries data with batch operations
  defp process_libraries_batch(server, libraries) when is_list(libraries) do
    Logger.info("Processing #{length(libraries)} libraries in batches")

    try do
      # Collect all existing jellyfin_ids
      existing_ids_query =
        from(l in Library,
          where: l.server_id == ^server.id,
          select: {l.jellyfin_id, l.id}
        )

      existing_map = Repo.all(existing_ids_query, timeout: @db_timeout) |> Map.new()

      # Split libraries into chunks
      libraries
      |> Enum.chunk_every(@batch_size)
      |> Enum.each(fn batch ->
        # Separate for insert and update
        {to_insert, to_update} =
          batch
          |> Enum.map(fn library ->
            attrs = %{
              jellyfin_id: library["Id"],
              name: library["Name"],
              type: library["CollectionType"] || "unknown",
              server_id: server.id
            }

            {attrs, Map.get(existing_map, attrs.jellyfin_id)}
          end)
          |> Enum.split_with(fn {_, id} -> is_nil(id) end)

        # Process inserts
        unless Enum.empty?(to_insert) do
          insert_attrs = Enum.map(to_insert, fn {attrs, _} -> attrs end)
          Repo.insert_all(Library, insert_attrs, on_conflict: :nothing, timeout: @db_timeout)
        end

        # Process updates one by one using a transaction
        Enum.each(to_update, fn {attrs, id} ->
          Repo.transaction(
            fn ->
              Repo.get(Library, id)
              |> Library.changeset(attrs)
              |> Repo.update(timeout: @db_timeout)
            end,
            timeout: @db_timeout
          )
        end)
      end)

      %{processed: length(libraries)}
    rescue
      e ->
        Logger.error("Error processing libraries: #{inspect(e)}")
        %{error: e, processed: 0}
    end
  end

  defp process_libraries_batch(_, _), do: %{processed: 0}

  # Process users data with batch operations
  defp process_users_batch(server, users) when is_list(users) do
    Logger.info("Processing #{length(users)} users in batches")

    try do
      # Collect all existing jellyfin_ids
      existing_ids_query =
        from(u in User,
          where: u.server_id == ^server.id,
          select: {u.jellyfin_id, u.id}
        )

      existing_map = Repo.all(existing_ids_query, timeout: @db_timeout) |> Map.new()

      # Split users into chunks
      users
      |> Enum.chunk_every(@batch_size)
      |> Enum.each(fn batch ->
        # Separate for insert and update
        {to_insert, to_update} =
          batch
          |> Enum.map(fn user ->
            attrs = %{
              jellyfin_id: user["Id"],
              name: user["Name"],
              is_administrator: user["IsAdministrator"],
              last_login_date: parse_jellyfin_date(user["LastLoginDate"]),
              last_activity_date: parse_jellyfin_date(user["LastActivityDate"]),
              server_id: server.id
            }

            {attrs, Map.get(existing_map, attrs.jellyfin_id)}
          end)
          |> Enum.split_with(fn {_, id} -> is_nil(id) end)

        # Process inserts
        unless Enum.empty?(to_insert) do
          insert_attrs = Enum.map(to_insert, fn {attrs, _} -> attrs end)
          Repo.insert_all(User, insert_attrs, on_conflict: :nothing, timeout: @db_timeout)
        end

        # Process updates one by one with transactions
        Enum.each(to_update, fn {attrs, id} ->
          Repo.transaction(
            fn ->
              Repo.get(User, id)
              |> User.changeset(attrs)
              |> Repo.update(timeout: @db_timeout)
            end,
            timeout: @db_timeout
          )
        end)
      end)

      %{processed: length(users)}
    rescue
      e ->
        Logger.error("Error processing users: #{inspect(e)}")
        %{error: e, processed: 0}
    end
  end

  defp process_users_batch(_, _), do: %{processed: 0}

  # Process items data with batch operations
  defp process_items_batch(server, items) when is_list(items) do
    Logger.info("Processing #{length(items)} media items in batches")

    try do
      # Preload all libraries for faster lookups - in its own transaction
      libraries_map =
        Repo.transaction(
          fn ->
            libraries_query =
              from(l in Library,
                where: l.server_id == ^server.id,
                select: {l.jellyfin_id, l}
              )

            Repo.all(libraries_query, timeout: @db_timeout) |> Map.new()
          end,
          timeout: @db_timeout
        )

      libraries_map =
        case libraries_map do
          {:ok, map} -> map
          _ -> %{}
        end

      # Collect all existing jellyfin_ids - in its own transaction
      existing_map =
        Repo.transaction(
          fn ->
            existing_ids_query =
              from(i in Item,
                where: i.server_id == ^server.id,
                select: {i.jellyfin_id, i.id}
              )

            Repo.all(existing_ids_query, timeout: @db_timeout) |> Map.new()
          end,
          timeout: @db_timeout
        )

      existing_map =
        case existing_map do
          {:ok, map} -> map
          _ -> %{}
        end

      # Split items into chunks
      items
      |> Enum.chunk_every(@batch_size)
      |> Enum.each(fn batch ->
        # Separate for insert and update
        {to_insert, to_update} =
          batch
          |> Enum.map(fn item ->
            # Find the library this item belongs to from our preloaded map
            library = if item["ParentId"], do: Map.get(libraries_map, item["ParentId"]), else: nil
            library_id = if library, do: library.id, else: nil

            type = item["Type"]

            # Jellystat saves Episdoes as Series, so we need to change it to Episode
            type = if type == "Series", do: "Episode", else: type

            attrs = %{
              jellyfin_id: item["Id"],
              name: item["Name"],
              type: type,
              original_title: item["OriginalTitle"],
              premiere_date: parse_jellyfin_date(item["PremiereDate"]),
              community_rating: item["CommunityRating"],
              runtime_ticks: item["RunTimeTicks"],
              production_year: item["ProductionYear"],
              is_folder: item["IsFolder"],
              parent_id: item["ParentId"],
              series_name: item["SeriesName"],
              series_id: item["SeriesId"],
              season_id: item["SeasonId"],
              primary_image_tag: item["ImageTagsPrimary"],
              backdrop_image_tags: to_array(item["BackdropImageTags"]),
              library_id: library_id,
              server_id: server.id
            }

            {attrs, Map.get(existing_map, attrs.jellyfin_id)}
          end)
          |> Enum.split_with(fn {_, id} -> is_nil(id) end)

        # Process inserts
        unless Enum.empty?(to_insert) do
          insert_attrs = Enum.map(to_insert, fn {attrs, _} -> attrs end)
          Repo.insert_all(Item, insert_attrs, on_conflict: :nothing, timeout: @db_timeout)
        end

        # Process updates one by one with transactions
        Enum.each(to_update, fn {attrs, id} ->
          Repo.transaction(
            fn ->
              Repo.get(Item, id)
              |> Item.changeset(attrs)
              |> Repo.update(timeout: @db_timeout)
            end,
            timeout: @db_timeout
          )
        end)
      end)

      %{processed: length(items)}
    rescue
      e ->
        Logger.error("Error processing items: #{inspect(e)}")
        %{error: e, processed: 0}
    end
  end

  defp process_items_batch(_, _), do: %{processed: 0}

  # Process playback activities with batch operations
  defp process_playback_activities_batch(server, activities) when is_list(activities) do
    Logger.info("Processing #{length(activities)} playback activities in batches")

    try do
      # Process in smaller batches to prevent crashes
      results =
        activities
        |> Enum.chunk_every(@batch_size)
        |> Enum.reduce(%{created: 0, updated: 0, skipped: 0, errors: 0}, fn batch, acc ->
          # Add error handling with retry logic around each batch
          case safe_process_batch(server, batch, acc) do
            {:ok, batch_results} ->
              # Combine results from this batch with overall results
              %{
                created: acc.created + batch_results.created,
                updated: acc.updated + batch_results.updated,
                skipped: acc.skipped + batch_results.skipped,
                errors: acc.errors + batch_results.errors
              }

            {:error, _reason} ->
              # Just count the entire batch as errors
              %{acc | errors: acc.errors + length(batch)}
          end
        end)

      Logger.info(
        "Processed #{length(activities)} playback activities: created=#{results.created}, updated=#{results.updated}, skipped=#{results.skipped}, errors=#{results.errors}"
      )

      results
    rescue
      e ->
        Logger.error("Error processing playback activities: #{inspect(e)}")
        %{created: 0, updated: 0, skipped: 0, errors: length(activities)}
    end
  end

  defp process_playback_activities_batch(_, _),
    do: %{created: 0, updated: 0, skipped: 0, errors: 0}

  # Safely load users in a separate transaction
  defp safely_load_users(server) do
    try do
      users_map =
        Repo.transaction(
          fn ->
            users_query =
              from(u in User,
                where: u.server_id == ^server.id,
                select: {u.jellyfin_id, u}
              )

            Repo.all(users_query, timeout: @db_timeout)
          end,
          timeout: @db_timeout
        )

      case users_map do
        {:ok, results} -> {:ok, Map.new(results)}
        error -> error
      end
    rescue
      e ->
        Logger.error("Error loading users: #{inspect(e)}")
        {:error, e}
    end
  end

  # Safely load items in a separate transaction
  defp safely_load_items(server) do
    try do
      items_map =
        Repo.transaction(
          fn ->
            items_query =
              from(i in Item,
                where: i.server_id == ^server.id,
                select: {i.jellyfin_id, i}
              )

            Repo.all(items_query, timeout: @db_timeout)
          end,
          timeout: @db_timeout
        )

      case items_map do
        {:ok, results} -> {:ok, Map.new(results)}
        error -> error
      end
    rescue
      e ->
        Logger.error("Error loading items: #{inspect(e)}")
        {:error, e}
    end
  end

  # Add a new function with retry logic for each batch
  defp safe_process_batch(server, batch, _acc, retry_count \\ 0) do
    # Preload users and items in separate transactions
    with {:ok, users_map} <- safely_load_users(server),
         {:ok, items_map} <- safely_load_items(server) do
      # Process the batch with the loaded maps
      try do
        results = process_playback_batch(server, batch, users_map, items_map)
        {:ok, results}
      rescue
        e in DBConnection.ConnectionError ->
          handle_db_error(e, server, batch, retry_count)

        e ->
          Logger.error("Error processing batch: #{inspect(e, pretty: true)}")
          Logger.error(Exception.format_stacktrace())
          {:error, e}
      end
    else
      {:error, reason} ->
        Logger.error("Failed to preload data: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp handle_db_error(error, server, batch, retry_count) do
    max_retries = 3

    if retry_count < max_retries do
      # Wait a bit before retrying (with exponential backoff)
      backoff = (:math.pow(2, retry_count) * 1000) |> round()

      Logger.warning(
        "Database error, retrying batch in #{backoff}ms (attempt #{retry_count + 1}/#{max_retries}): #{inspect(error.message)}"
      )

      :timer.sleep(backoff)
      safe_process_batch(server, batch, %{}, retry_count + 1)
    else
      Logger.error(
        "Failed to process batch after #{max_retries} attempts: #{inspect(error.message)}"
      )

      {:error, error}
    end
  end

  defp process_playback_batch(server, activities, users_map, items_map) do
    # Get the item and user ids directly
    item_ids =
      Enum.map(activities, fn activity ->
        activity["EpisodeId"] || activity["NowPlayingItemId"]
      end)
      |> Enum.reject(&is_nil/1)

    user_ids =
      Enum.map(activities, fn activity -> activity["UserId"] end)
      |> Enum.reject(&is_nil/1)

    # Skip the query if we have no valid IDs
    existing_sessions =
      if Enum.empty?(item_ids) || Enum.empty?(user_ids) do
        %{}
      else
        # Query for existing sessions in a smaller transaction
        try do
          query_result =
            Repo.transaction(
              fn ->
                existing_query =
                  from(s in PlaybackSession,
                    where:
                      s.server_id == ^server.id and
                        s.item_jellyfin_id in ^item_ids and
                        s.user_jellyfin_id in ^user_ids,
                    select: {s.item_jellyfin_id, s.user_jellyfin_id, s.start_time, s}
                  )

                Repo.all(existing_query, timeout: @db_timeout)
              end,
              timeout: @db_timeout
            )

          case query_result do
            {:ok, existing_sessions_list} ->
              # Convert to map for easier lookup
              Enum.reduce(existing_sessions_list, %{}, fn {item_id, user_id, start_time, session},
                                                          acc ->
                Map.put(acc, {item_id, user_id, start_time}, session)
              end)

            _ ->
              %{}
          end
        rescue
          e ->
            Logger.error("Error querying existing sessions: #{inspect(e)}")
            %{}
        end
      end

    # Process each activity using smaller transactions
    Enum.reduce(activities, %{created: 0, updated: 0, skipped: 0, errors: 0}, fn activity, acc ->
      try do
        result =
          Repo.transaction(
            fn ->
              create_playback_session_from_jellystats(
                server,
                activity,
                users_map,
                items_map,
                existing_sessions
              )
            end,
            timeout: @db_timeout
          )

        case result do
          {:ok, {:ok, :created, _}} -> Map.update!(acc, :created, &(&1 + 1))
          {:ok, {:ok, :updated, _}} -> Map.update!(acc, :updated, &(&1 + 1))
          {:ok, {:skip, _}} -> Map.update!(acc, :skipped, &(&1 + 1))
          _ -> Map.update!(acc, :errors, &(&1 + 1))
        end
      rescue
        _ -> Map.update!(acc, :errors, &(&1 + 1))
      end
    end)
  end

  defp create_playback_session_from_jellystats(
         server,
         activity,
         users_map,
         items_map,
         existing_sessions
       ) do
    try do
      user_jellyfin_id = activity["UserId"]
      user = Map.get(users_map, user_jellyfin_id)

      unless user do
        {:skip, "User not found in database"}
      else
        activity_date = parse_jellyfin_date(activity["ActivityDateInserted"])
        play_duration = String.to_integer(activity["PlaybackDuration"])
        item_jellyfin_id = activity["EpisodeId"] || activity["NowPlayingItemId"]

        item = Map.get(items_map, item_jellyfin_id)

        runtime_ticks =
          case item do
            %Item{runtime_ticks: ticks} when not is_nil(ticks) -> ticks
            _ -> 0
          end

        percent_complete =
          if runtime_ticks > 0 do
            # Convert play_duration from seconds to ticks for comparison
            play_duration_ticks = play_duration * 10_000
            # Calculate percentage
            play_duration_ticks / runtime_ticks * 100.0
          else
            # Default to 0 if we can't calculate
            0.0
          end

        # Session is considered completed if progress is > 90%
        completed = percent_complete > 90.0

        end_time =
          if activity_date && play_duration && play_duration > 0 do
            DateTime.add(activity_date, play_duration, :second)
          else
            nil
          end

        series_jellyfin_id = activity["NowPlayingItemId"]
        season_jellyfin_id = activity["SeasonId"]

        attrs = %{
          user_id: user && user.id,
          user_jellyfin_id: user_jellyfin_id,
          device_id: activity["DeviceId"],
          device_name: activity["DeviceName"],
          client_name: activity["Client"],
          item_jellyfin_id: item_jellyfin_id,
          item_name: activity["NowPlayingItemName"],
          series_jellyfin_id: series_jellyfin_id,
          series_name: activity["SeriesName"],
          season_jellyfin_id: season_jellyfin_id,
          play_duration: play_duration,
          play_method: activity["PlayMethod"],
          start_time: activity_date,
          end_time: end_time,
          position_ticks: activity["PlayState"]["PositionTicks"],
          runtime_ticks: runtime_ticks,
          percent_complete: percent_complete,
          completed: completed,
          server_id: server.id
        }

        # Check if this session already exists in our lookup map
        existing_key = {item_jellyfin_id, user_jellyfin_id, activity_date}
        existing_session = Map.get(existing_sessions, existing_key)

        if is_nil(existing_session) do
          result =
            %PlaybackSession{}
            |> PlaybackSession.changeset(attrs)
            |> Repo.insert(timeout: @db_timeout)

          case result do
            {:ok, session} ->
              {:ok, :created, session}

            {:error, changeset} ->
              Logger.error("Failed to create playback session: #{inspect(changeset.errors)}")
              {:error, changeset}
          end
        else
          # Only update if the new data has more information
          if should_update_session?(existing_session, attrs) do
            result =
              existing_session
              |> PlaybackSession.changeset(attrs)
              |> Repo.update(timeout: @db_timeout)

            case result do
              {:ok, session} ->
                {:ok, :updated, session}

              {:error, changeset} ->
                Logger.error("Failed to update playback session: #{inspect(changeset.errors)}")
                {:error, changeset}
            end
          else
            {:skip, "Existing session has better data"}
          end
        end
      end
    catch
      _ -> {:error, "Unexpected error occurred"}
    end
  end

  # Helper functions

  defp should_update_session?(existing, new) do
    # Update if:
    # 1. New session has longer duration
    # 2. New session has more progress
    # 3. New session has more complete data
    new.play_duration > existing.play_duration ||
      (new.position_ticks || 0) > (existing.position_ticks || 0) ||
      (is_nil(existing.end_time) && !is_nil(new.end_time))
  end

  defp parse_jellyfin_date(nil), do: nil

  defp parse_jellyfin_date(date) when is_binary(date) do
    case DateTime.from_iso8601(date) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end

  defp to_array(value) when is_list(value), do: value
  defp to_array(value) when is_binary(value), do: [value]
  defp to_array(_), do: []
end
