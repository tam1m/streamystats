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
  @batch_size 100

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
    {:ok, %{importing: false}}
  end

  @impl true
  def handle_cast({:import, server_id, json_data}, state) do
    if state.importing do
      Logger.info("Jellystats import already in progress, skipping.")
      {:noreply, state}
    else
      Logger.info("Starting Jellystats import for server_id: #{server_id}")

      # Spawn the import process
      Task.start(fn ->
        do_import(server_id, json_data)
        GenServer.cast(__MODULE__, :import_complete)
      end)

      {:noreply, %{state | importing: true}}
    end
  end

  @impl true
  def handle_cast(:import_complete, state) do
    Logger.info("Jellystats import completed")
    {:noreply, %{state | importing: false}}
  end

  defp do_import(server_id, json_data) do
    Logger.debug("Looking up server with ID: #{server_id}")

    server = Repo.get(Server, server_id)

    if server do
      Logger.info("Found server: #{server.name} (ID: #{server.id})")

      # Decode the JSON data if it's a string
      data = decode_data(json_data)

      # Process the data sections
      process_jellystats_data(server, data)
    else
      Logger.error("Server with ID #{server_id} not found")
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
    # Process each type of data in a transaction
    Repo.transaction(fn ->
      # Get the data from the correct structure
      libraries = get_in(data, ["jf_libraries"]) || []
      users = get_in(data, ["jf_users"]) || []
      items = get_in(data, ["jf_library_items"]) || []
      activities = get_in(data, ["jf_playback_activity"]) || []

      # Process each type of data
      process_libraries_batch(server, libraries)
      process_users_batch(server, users)
      process_items_batch(server, items)
      results = process_playback_activities_batch(server, activities)
      results
    end)
  end

  defp process_jellystats_data(server, data) do
    # Log the received data structure
    Logger.debug("Processing data structure: #{inspect(data, pretty: true)}")

    # Process each type of data in a transaction
    Repo.transaction(fn ->
      # Get the data from the correct structure
      # Handle both single object and array cases
      data_list = if is_list(data), do: data, else: [data]

      libraries =
        data_list
        |> Enum.flat_map(& &1["jf_libraries"] || [])
        |> Enum.uniq_by(& &1["Id"])

      users =
        data_list
        |> Enum.flat_map(& &1["jf_users"] || [])
        |> Enum.uniq_by(& &1["Id"])

      items =
        data_list
        |> Enum.flat_map(& &1["jf_library_items"] || [])
        |> Enum.uniq_by(& &1["Id"])

      activities =
        data_list
        |> Enum.flat_map(& &1["jf_playback_activity"] || [])
        |> Enum.uniq_by(& &1["Id"])

      # Log counts for debugging
      Logger.info("Found: #{length(libraries)} libraries, #{length(users)} users, " <>
                 "#{length(items)} items, #{length(activities)} activities")

      # Process each type of data in batches
      process_libraries_batch(server, libraries)
      process_users_batch(server, users)
      process_items_batch(server, items)
      results = process_playback_activities_batch(server, activities)

      Logger.info("Jellystats import results: #{inspect(results)}")
      results
    end)
  end

  defp process_jellystats_data(_server, data) do
    Logger.error("Invalid data structure for Jellystats import: #{inspect(data)}")
    {:error, "Invalid data structure"}
  end

  # Process libraries data with batch operations
  defp process_libraries_batch(server, libraries) when is_list(libraries) do
    Logger.info("Processing #{length(libraries)} libraries in batches")

    # Collect all existing jellyfin_ids
    existing_ids_query = from l in Library,
                         where: l.server_id == ^server.id,
                         select: {l.jellyfin_id, l.id}
    existing_map = Repo.all(existing_ids_query) |> Map.new()

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
        Repo.insert_all(Library, insert_attrs, on_conflict: :nothing)
      end

      # Process updates one by one (could be optimized with upsert in PostgreSQL)
      to_update
      |> Enum.each(fn {attrs, id} ->
        Repo.get(Library, id)
        |> Library.changeset(attrs)
        |> Repo.update()
      end)
    end)
  end
  defp process_libraries_batch(_, _), do: :ok

  # Process users data with batch operations
  defp process_users_batch(server, users) when is_list(users) do
    Logger.info("Processing #{length(users)} users in batches")

    # Collect all existing jellyfin_ids
    existing_ids_query = from u in User,
                         where: u.server_id == ^server.id,
                         select: {u.jellyfin_id, u.id}
    existing_map = Repo.all(existing_ids_query) |> Map.new()

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
        Repo.insert_all(User, insert_attrs, on_conflict: :nothing)
      end

      # Process updates one by one
      to_update
      |> Enum.each(fn {attrs, id} ->
        Repo.get(User, id)
        |> User.changeset(attrs)
        |> Repo.update()
      end)
    end)
  end
  defp process_users_batch(_, _), do: :ok

  # Process items data with batch operations
  defp process_items_batch(server, items) when is_list(items) do
    Logger.info("Processing #{length(items)} media items in batches")

    # Preload all libraries for faster lookups
    libraries_query = from l in Library,
                      where: l.server_id == ^server.id,
                      select: {l.jellyfin_id, l}
    libraries_map = Repo.all(libraries_query) |> Map.new()

    # Collect all existing jellyfin_ids
    existing_ids_query = from i in Item,
                         where: i.server_id == ^server.id,
                         select: {i.jellyfin_id, i.id}
    existing_map = Repo.all(existing_ids_query) |> Map.new()

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

          attrs = %{
            jellyfin_id: item["Id"],
            name: item["Name"],
            type: item["Type"],
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
        Repo.insert_all(Item, insert_attrs, on_conflict: :nothing)
      end

      # Process updates one by one
      to_update
      |> Enum.each(fn {attrs, id} ->
        Repo.get(Item, id)
        |> Item.changeset(attrs)
        |> Repo.update()
      end)
    end)
  end
  defp process_items_batch(_, _), do: :ok

  # Process playback activities with batch operations
  defp process_playback_activities_batch(server, activities) when is_list(activities) do
    Logger.info("Processing #{length(activities)} playback activities in batches")

    # Preload all users for faster lookups
    users_query = from u in User,
                  where: u.server_id == ^server.id,
                  select: {u.jellyfin_id, u}
    users_map = Repo.all(users_query) |> Map.new()

    # Preload all items for faster lookups
    items_query = from i in Item,
                  where: i.server_id == ^server.id,
                  select: {i.jellyfin_id, i}
    items_map = Repo.all(items_query) |> Map.new()

    # Process in smaller batches to prevent crashes
    results = activities
    |> Enum.chunk_every(@batch_size)
    |> Enum.reduce(%{created: 0, updated: 0, skipped: 0, errors: 0}, fn batch, acc ->
      batch_results = process_playback_batch(server, batch, users_map, items_map)

      # Combine results from this batch with overall results
      %{
        created: acc.created + batch_results.created,
        updated: acc.updated + batch_results.updated,
        skipped: acc.skipped + batch_results.skipped,
        errors: acc.errors + batch_results.errors
      }
    end)

    Logger.info("Processed #{length(activities)} playback activities: created=#{results.created}, updated=#{results.updated}, skipped=#{results.skipped}, errors=#{results.errors}")

    results
  end
  defp process_playback_activities_batch(_, _), do: %{created: 0, updated: 0, skipped: 0, errors: 0}

  defp process_playback_batch(server, activities, users_map, items_map) do
    # Prepare lookup data
    item_ids = Enum.map(activities, fn activity ->
      activity["EpisodeId"] || activity["NowPlayingItemId"]
    end)
    user_ids = Enum.map(activities, fn activity -> activity["UserId"] end)

    # Query for existing sessions - using separate parameters rather than a tuple
    existing_query = from s in PlaybackSession,
                     where: s.server_id == ^server.id and
                            s.item_jellyfin_id in ^item_ids and
                            s.user_jellyfin_id in ^user_ids,
                     select: {s.item_jellyfin_id, s.user_jellyfin_id, s.start_time, s}

    existing_sessions_list = Repo.all(existing_query)

    # Convert to map for easier lookup
    existing_sessions = Enum.reduce(existing_sessions_list, %{}, fn {item_id, user_id, start_time, session}, acc ->
      Map.put(acc, {item_id, user_id, start_time}, session)
    end)

    # Process each activity
    Enum.reduce(activities, %{created: 0, updated: 0, skipped: 0, errors: 0}, fn activity, acc ->
      case create_playback_session_from_jellystats(server, activity, users_map, items_map, existing_sessions) do
        {:ok, :created, _} -> Map.update!(acc, :created, &(&1 + 1))
        {:ok, :updated, _} -> Map.update!(acc, :updated, &(&1 + 1))
        {:skip, _} -> Map.update!(acc, :skipped, &(&1 + 1))
        {:error, _} -> Map.update!(acc, :errors, &(&1 + 1))
      end
    end)
  end

  defp create_playback_session_from_jellystats(server, activity, users_map, items_map, existing_sessions) do
    try do
      # Get the user ID
      user_jellyfin_id = activity["UserId"]

      unless user_jellyfin_id do
        Logger.warn("Activity missing UserId: #{inspect(activity)}")
        {:skip, "Missing UserId"}
      else
        # Look up the user in our preloaded map
        user = Map.get(users_map, user_jellyfin_id)

        # Skip if user not found in database
        unless user do
          Logger.warn("User not found for jellyfin_id: #{user_jellyfin_id}, skipping session")
          {:skip, "User not found in database"}
        else
          # Extract dates
          activity_date = parse_jellyfin_date(activity["ActivityDateInserted"])

          unless activity_date do
            Logger.warn("Invalid or missing ActivityDateInserted: #{activity["ActivityDateInserted"]}")
            {:skip, "Invalid activity date"}
          else
            # Extract position and duration from PlayState
            play_state = activity["PlayState"] || %{}
            position_ticks = play_state["PositionTicks"]

            # Calculate play duration from the PlaybackDuration field (in seconds)
            play_duration =
              case activity["PlaybackDuration"] do
                x when is_binary(x) -> String.to_integer(x)
                x when is_integer(x) -> x
                _ -> 0
              end

            # Item ID for lookup
            item_jellyfin_id = activity["EpisodeId"] || activity["NowPlayingItemId"]

            # Get item from preloaded map
            item = Map.get(items_map, item_jellyfin_id)

            # Try to get runtime_ticks from different sources
            runtime_ticks =
              case activity["NowPlayingItem"] do
                %{"RunTimeTicks" => ticks} when is_integer(ticks) -> ticks
                _ ->
                  case item do
                    %Item{runtime_ticks: ticks} when not is_nil(ticks) -> ticks
                    _ -> 0
                  end
              end

            # Safely calculate percent complete
            percent_complete =
              if position_ticks && runtime_ticks && runtime_ticks > 0 do
                percentage = position_ticks / runtime_ticks * 100
                Float.round(percentage, 2)
              else
                0.0
              end

            # Session is considered completed if progress is > 90%
            completed = percent_complete > 90.0

            # Calculate end time
            end_time =
              if activity_date && play_duration && play_duration > 0 do
                DateTime.add(activity_date, play_duration, :second)
              else
                nil
              end

            # Corrected mapping for series/season/episode IDs
            series_jellyfin_id = activity["SeriesId"] || activity["NowPlayingItemId"]
            season_jellyfin_id = activity["SeasonId"]

            # Build the attributes map
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
              play_method: play_state["PlayMethod"] || activity["PlayMethod"],
              start_time: activity_date,
              end_time: end_time,
              position_ticks: position_ticks,
              runtime_ticks: runtime_ticks,
              percent_complete: percent_complete,
              completed: completed,
              server_id: server.id
            }

            # Check if this session already exists in our lookup map
            existing_key = {item_jellyfin_id, user_jellyfin_id, activity_date}
            existing_session = Map.get(existing_sessions, existing_key)

            if is_nil(existing_session) do
              result = %PlaybackSession{}
              |> PlaybackSession.changeset(attrs)
              |> Repo.insert()

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
                result = existing_session
                |> PlaybackSession.changeset(attrs)
                |> Repo.update()

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
        end
      end
    rescue
      e ->
        Logger.error("Exception processing playback activity: #{inspect(e, pretty: true)}")
        Logger.error("Activity: #{inspect(activity, pretty: true)}")
        {:error, e}
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
