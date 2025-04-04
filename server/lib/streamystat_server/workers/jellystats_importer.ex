defmodule StreamystatServer.Workers.JellystatsImporter do
  use GenServer
  require Logger
  alias StreamystatServer.Repo
  alias StreamystatServer.Servers.Models.Server
  alias StreamystatServer.Jellyfin.Models.User
  alias StreamystatServer.Jellyfin.Models.Library
  alias StreamystatServer.Jellyfin.Models.Item
  alias StreamystatServer.Sessions.Models.PlaybackSession

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
      process_libraries(server, libraries)
      process_users(server, users)
      process_items(server, items)
      results = process_playback_activities(server, activities)

      Logger.info("Jellystats import results: #{inspect(results)}")
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

      # Process each type of data
      process_libraries(server, libraries)
      process_users(server, users)
      process_items(server, items)
      results = process_playback_activities(server, activities)

      Logger.info("Jellystats import results: #{inspect(results)}")
      results
    end)
  end

  defp process_jellystats_data(_server, data) do
    Logger.error("Invalid data structure for Jellystats import: #{inspect(data)}")
    {:error, "Invalid data structure"}
  end

  # Process libraries data (optional, enhances our data)
  defp process_libraries(server, libraries) when is_list(libraries) do
    Logger.info("Processing #{length(libraries)} libraries")

    libraries
    |> Enum.each(fn library ->
      attrs = %{
        jellyfin_id: library["Id"],
        name: library["Name"],
        type: library["CollectionType"] || "unknown",
        server_id: server.id
      }

      case Repo.get_by(Library, jellyfin_id: attrs.jellyfin_id, server_id: server.id) do
        nil ->
          %Library{}
          |> Library.changeset(attrs)
          |> Repo.insert(on_conflict: :nothing)

        library ->
          library
          |> Library.changeset(attrs)
          |> Repo.update()
      end
    end)
  end
  defp process_libraries(_, _), do: :ok

  # Process users data
  defp process_users(server, users) when is_list(users) do
    Logger.info("Processing #{length(users)} users")

    users
    |> Enum.each(fn user ->
      attrs = %{
        jellyfin_id: user["Id"],
        name: user["Name"],
        is_administrator: user["IsAdministrator"],
        last_login_date: parse_jellyfin_date(user["LastLoginDate"]),
        last_activity_date: parse_jellyfin_date(user["LastActivityDate"]),
        server_id: server.id
      }

      case Repo.get_by(User, jellyfin_id: attrs.jellyfin_id, server_id: server.id) do
        nil ->
          %User{}
          |> User.changeset(attrs)
          |> Repo.insert(on_conflict: :nothing)

        existing_user ->
          existing_user
          |> User.changeset(attrs)
          |> Repo.update()
      end
    end)
  end
  defp process_users(_, _), do: :ok

  # Process items data (movies, episodes, etc.)
  defp process_items(server, items) when is_list(items) do
    Logger.info("Processing #{length(items)} media items")

    items
    |> Enum.each(fn item ->
      # Find the library this item belongs to
      library =
        if item["ParentId"] do
          Repo.get_by(Library, jellyfin_id: item["ParentId"], server_id: server.id)
        else
          nil
        end

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

      case Repo.get_by(Item, jellyfin_id: attrs.jellyfin_id, server_id: server.id) do
        nil ->
          %Item{}
          |> Item.changeset(attrs)
          |> Repo.insert(on_conflict: :nothing)

        existing_item ->
          existing_item
          |> Item.changeset(attrs)
          |> Repo.update()
      end
    end)
  end

  defp process_items(_, _), do: :ok

  # Process playback activities
  defp process_playback_activities(server, activities) when is_list(activities) do
    Logger.info("Processing #{length(activities)} playback activities")

    results = Enum.reduce(activities, %{created: 0, updated: 0, skipped: 0, errors: 0}, fn activity, acc ->
      case create_playback_session_from_jellystats(server, activity) do
        {:ok, :created, _} -> Map.update!(acc, :created, &(&1 + 1))
        {:ok, :updated, _} -> Map.update!(acc, :updated, &(&1 + 1))
        {:skip, _} -> Map.update!(acc, :skipped, &(&1 + 1))
        {:error, _} -> Map.update!(acc, :errors, &(&1 + 1))
      end
    end)

    Logger.info("Processed #{length(activities)} playback activities: created=#{results.created}, updated=#{results.updated}, skipped=#{results.skipped}, errors=#{results.errors}")

    results
  end

  defp create_playback_session_from_jellystats(server, activity) do
    try do
      # Log the activity being processed
      Logger.debug("Processing activity: #{inspect(activity, pretty: true)}")

      # Get the user ID
      user_jellyfin_id = activity["UserId"]

      unless user_jellyfin_id do
        Logger.warn("Activity missing UserId: #{inspect(activity)}")
        {:skip, "Missing UserId"}
      else
        # Look up the user in our database
        user = Repo.get_by(User, jellyfin_id: user_jellyfin_id, server_id: server.id)

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

            # Try to get runtime_ticks from different sources
            runtime_ticks =
              case activity["NowPlayingItem"] do
                %{"RunTimeTicks" => ticks} when is_integer(ticks) -> ticks
                _ ->
                  case get_item_by_id(server, activity["EpisodeId"] || activity["NowPlayingItemId"]) do
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
            item_jellyfin_id = activity["EpisodeId"] || activity["NowPlayingItemId"]
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

            # Log the processed attributes
            Logger.debug("Processed attributes: #{inspect(attrs, pretty: true)}")

            # Generate a unique session identifier similar to SessionPoller
            session_key = generate_session_key(activity)

            case find_existing_session(server.id, attrs.item_jellyfin_id, attrs.user_jellyfin_id, attrs.start_time) do
              nil ->
                result = %PlaybackSession{}
                |> PlaybackSession.changeset(attrs)
                |> Repo.insert()

                case result do
                  {:ok, session} ->
                    Logger.info(
                      "Created new playback session from Jellystats: " <>
                      "ID #{session.id}, User #{attrs.user_jellyfin_id}, " <>
                      "Item #{attrs.item_name}, Duration #{play_duration}s, " <>
                      "Progress #{percent_complete}%, " <>
                      "Completed: #{completed}"
                    )
                    {:ok, :created, session}
                  {:error, changeset} ->
                    Logger.error("Failed to create playback session: #{inspect(changeset.errors)}")
                    {:error, changeset}
                end

              existing_session ->
                # Only update if the new data has more information
                if should_update_session?(existing_session, attrs) do
                  result = existing_session
                  |> PlaybackSession.changeset(attrs)
                  |> Repo.update()

                  case result do
                    {:ok, session} ->
                      Logger.info("Updated existing playback session: ID #{session.id}")
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

  defp generate_session_key(activity) do
    user_id = activity["UserId"] || ""
    device_id = activity["DeviceId"] || ""
    item_id = activity["EpisodeId"] || activity["NowPlayingItemId"] || ""
    series_id = activity["SeriesId"] || ""

    if series_id != "" do
      "#{user_id}|#{device_id}|#{series_id}|#{item_id}"
    else
      "#{user_id}|#{device_id}|#{item_id}"
    end
  end

  defp get_item_by_id(server, item_id) do
    Repo.get_by(Item, jellyfin_id: item_id, server_id: server.id)
  end

  defp should_update_session?(existing, new) do
    # Update if:
    # 1. New session has longer duration
    # 2. New session has more progress
    # 3. New session has more complete data
    new.play_duration > existing.play_duration ||
      (new.position_ticks || 0) > (existing.position_ticks || 0) ||
      (is_nil(existing.end_time) && !is_nil(new.end_time))
  end

  defp find_existing_session(server_id, item_id, user_id, start_time) do
    # Find an existing session with the same key attributes
    Repo.get_by(PlaybackSession,
      server_id: server_id,
      item_jellyfin_id: item_id,
      user_jellyfin_id: user_id,
      start_time: start_time
    )
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
