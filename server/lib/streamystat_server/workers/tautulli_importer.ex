defmodule StreamystatServer.Workers.TautulliImporter do
  use GenServer
  require Logger
  alias StreamystatServer.Repo
  alias StreamystatServer.Servers.Models.Server
  alias StreamystatServer.Jellyfin.Models.User
  alias StreamystatServer.Sessions.Models.PlaybackSession

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def import_data(server_id, tautulli_url, api_key, mappings \\ %{}) do
    # Parse mappings if they're still in string format
    mappings = process_mappings(mappings)
    GenServer.cast(__MODULE__, {:import, server_id, tautulli_url, api_key, mappings})
  end

  # Process mappings to ensure they're in the right format
  defp process_mappings(%{library_mappings: lib, user_mappings: user}) do
    %{
      library_mappings: parse_json_if_needed(lib),
      user_mappings: parse_json_if_needed(user)
    }
  end

  defp process_mappings(mappings), do: mappings

  defp parse_json_if_needed(value) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, parsed} ->
        Logger.info("Successfully parsed JSON mapping: #{inspect(parsed, pretty: true)}")
        parsed
      {:error, error} ->
        Logger.error("Failed to parse JSON mapping: #{inspect(error)}")
        []
    end
  end

  defp parse_json_if_needed(value), do: value

  # Server Callbacks

  @impl true
  def init(_opts) do
    {:ok, %{importing: false}}
  end

  @impl true
  def handle_cast({:import, server_id, tautulli_url, api_key, mappings}, state) do
    if state.importing do
      Logger.info("Tautulli import already in progress, skipping.")
      {:noreply, state}
    else
      Logger.info("Starting Tautulli import for server_id: #{server_id}")
      Logger.info("Using processed mappings: #{inspect(mappings, pretty: true)}")

      # Spawn the import process
      Task.start(fn ->
        do_import(server_id, tautulli_url, api_key, mappings)
        GenServer.cast(__MODULE__, :import_complete)
      end)

      {:noreply, %{state | importing: true}}
    end
  end

  @impl true
  def handle_cast(:import_complete, state) do
    Logger.info("Tautulli import completed")
    {:noreply, %{state | importing: false}}
  end

  # Private functions

  defp do_import(server_id, tautulli_url, api_key, mappings) do
    Logger.debug("Looking up server with ID: #{server_id}")

    server = Repo.get(Server, server_id)

    if server do
      Logger.info("Found server: #{server.name} (ID: #{server.id})")

      # Preload user and item mappings
      mappings = preload_user_mappings(mappings)

      fetch_and_process_tautulli_data(server, tautulli_url, api_key, mappings)
    else
      Logger.error("Server with ID #{server_id} not found")
    end
  end

  # Preload User objects for all user mappings
  defp preload_user_mappings(%{user_mappings: mappings} = all_mappings) when is_list(mappings) do
    # Convert mappings to include the actual User objects
    loaded_mappings = Enum.map(mappings, fn mapping ->
      case mapping do
        %{"jellyfinUserId" => user_db_id} ->
          # Fetch the User record to get the jellyfin_id
          case Repo.get(User, user_db_id) do
            %User{} = user ->
              Logger.info("Found user with ID #{user_db_id} - jellyfin_id: #{user.jellyfin_id}")
              Map.put(mapping, "user", user)
            nil ->
              Logger.warning("User with ID #{user_db_id} not found in database")
              mapping
          end
        _ -> mapping
      end
    end)

    Map.put(all_mappings, :user_mappings, loaded_mappings)
  end

  defp preload_user_mappings(mappings), do: mappings

  defp fetch_and_process_tautulli_data(server, tautulli_url, api_key, mappings) do
    start = 0
    length = 100
    total_processed = 0

    Logger.info("Starting Tautulli data import for server: #{server.name}")
    Logger.info("Using mappings: #{inspect(mappings, pretty: true)}")

    fetch_page_and_continue(server, tautulli_url, api_key, start, length, total_processed, mappings)
  end

  defp fetch_page_and_continue(server, tautulli_url, api_key, start, length, total_processed, mappings) do
    url = "#{tautulli_url}/api/v2?apikey=#{api_key}&cmd=get_history&start=#{start}&length=#{length}"
    Logger.debug("Fetching Tautulli data from: #{url}")

    with {:ok, %HTTPoison.Response{status_code: 200, body: body}} <- HTTPoison.get(url),
         {:ok, response} <- Jason.decode(body),
         %{"response" => %{"data" => %{"data" => records}}} <- response do

      # Log sample of records for debugging
      if start == 0 do
        sample = Enum.take(records, 2)
        Logger.info("Sample Tautulli records: #{inspect(sample, pretty: true)}")
      end

      # Process this batch of records
      {success, error, skipped} = process_records(server, records, mappings)

      records_count = length(records)
      new_total = total_processed + records_count

      Logger.info("Processed #{records_count} records from Tautulli (success: #{success}, errors: #{error}, skipped: #{skipped}, total processed: #{new_total})")

      # If we got a full page, there might be more data
      if records_count == length do
        # Continue with the next page
        fetch_page_and_continue(server, tautulli_url, api_key, start + length, length, new_total, mappings)
      else
        Logger.info("Tautulli import completed. Total records imported: #{new_total}")
      end
    else
      {:ok, %HTTPoison.Response{status_code: status}} ->
        Logger.error("Failed to fetch Tautulli data. Status code: #{status}")

      {:error, error} ->
        Logger.error("Error fetching Tautulli data: #{inspect(error)}")

      error ->
        Logger.error("Unexpected error during Tautulli import: #{inspect(error)}")
    end
  end

  defp process_records(server, records, mappings) do
    # Track success, error, and skipped counts
    results = Repo.transaction(fn ->
      Enum.reduce(records, {0, 0, 0}, fn record, {success, error, skipped} ->
        case safe_create_playback_session(server, record, mappings) do
          {:ok, _} -> {success + 1, error, skipped}
          {:skip, reason} ->
            Logger.info("Skipped record: #{reason}")
            {success, error, skipped + 1}
          {:error, reason} ->
            Logger.warning("Failed to process record: #{inspect(reason)}")
            {success, error + 1, skipped}
        end
      end)
    end)

    case results do
      {:ok, counts} -> counts
      {:error, _} -> {0, 0, length(records)}
    end
  end

  # Safely attempt to create a session with error handling
  defp safe_create_playback_session(server, record, mappings) do
    try do
      create_playback_session_from_tautulli(server, record, mappings)
    rescue
      e ->
        Logger.error("Exception while processing record: #{inspect(e)}")
        Logger.error("Record data: #{inspect(record, pretty: true)}")
        {:error, e}
    end
  end

  defp create_playback_session_from_tautulli(server, record, mappings) do
    # Log the raw record
    Logger.debug("Processing Tautulli record: #{inspect(record, pretty: true)}")

    # Get the Tautulli user ID
    tautulli_user_id = record["user_id"]

    # Get the user and jellyfin_id
    case get_user_and_jellyfin_id(tautulli_user_id, mappings) do
      {:ok, user, jellyfin_user_id} ->
        # Continue with the import using this user
        Logger.info("User mapping: Tautulli ID #{tautulli_user_id} -> User ID #{user.id} -> Jellyfin ID #{jellyfin_user_id}")

        # For items and series, we just use a placeholder ID for now
        # In a real implementation, this is where you would use your mapping logic
        # to find the correct Jellyfin IDs for these items
        tautulli_item_id = record["rating_key"]
        jellyfin_item_id = "tautulli_item_#{tautulli_item_id}"  # Just a placeholder

        Logger.info("Item mapping: Using placeholder jellyfin_item_id: #{jellyfin_item_id}")

        # Series and season IDs - also use placeholders
        tautulli_series_id = record["grandparent_rating_key"]
        jellyfin_series_id = tautulli_series_id && "tautulli_series_#{tautulli_series_id}"

        tautulli_season_id = record["parent_rating_key"]
        jellyfin_season_id = tautulli_season_id && "tautulli_season_#{tautulli_season_id}"

        # Extract dates
        start_time = parse_tautulli_date(record["started"])
        end_time = record["stopped"] && parse_tautulli_date(record["stopped"])

        # Map Tautulli record to our PlaybackSession schema
        attrs = %{
          user_id: user.id,                     # Set user_id from our database
          user_jellyfin_id: jellyfin_user_id,   # Use the real jellyfin_id
          device_id: record["machine_id"] || generate_fallback_device_id(record),
          device_name: record["platform"] || "Unknown Platform",
          client_name: record["player"] || "Unknown Player",
          item_jellyfin_id: jellyfin_item_id,   # Use the placeholder for now
          item_name: record["full_title"] || "Unknown Title",
          series_jellyfin_id: jellyfin_series_id,
          series_name: record["grandparent_title"],
          season_jellyfin_id: jellyfin_season_id,
          play_duration: record["play_duration"] || 0,
          play_method: map_transcode_decision(record["transcode_decision"]),
          start_time: start_time,
          end_time: end_time,
          server_id: server.id,
          position_ticks: nil,
          runtime_ticks: nil,
          percent_complete: record["percent_complete"] || 0,
          completed: (record["percent_complete"] || 0) >= 90  # Consider completed if >90%
        }

        # Log the mapped attributes
        Logger.debug("Mapped to PlaybackSession: #{inspect(attrs, pretty: true)}")

        # Find or create the playback session
        case find_existing_session(server.id, attrs.item_jellyfin_id, attrs.user_jellyfin_id, attrs.start_time) do
          nil ->
            Logger.debug("Creating new PlaybackSession")
            result = %PlaybackSession{}
            |> PlaybackSession.changeset(attrs)
            |> Repo.insert()

            case result do
              {:ok, session} ->
                Logger.info("Created new playback session: ID #{session.id}, User #{attrs.user_jellyfin_id}, Item #{attrs.item_name}")
                {:ok, {:created, session}}
              {:error, changeset} ->
                Logger.error("Failed to create playback session: #{inspect(changeset.errors)}")
                {:error, changeset}
            end

          session ->
            # Update existing session if needed
            Logger.debug("Updating existing PlaybackSession ID: #{session.id}")
            result = session
            |> PlaybackSession.changeset(attrs)
            |> Repo.update()

            case result do
              {:ok, session} ->
                Logger.info("Updated existing playback session: ID #{session.id}")
                {:ok, {:updated, session}}
              {:error, changeset} ->
                Logger.error("Failed to update playback session: #{inspect(changeset.errors)}")
                {:error, changeset}
            end
        end

      {:skip, reason} ->
        # Skip this record
        {:skip, reason}
    end
  end

  # Get both the user and the jellyfin_id
  defp get_user_and_jellyfin_id(tautulli_user_id, %{user_mappings: mappings}) when is_list(mappings) do
    # Find matching mapping with user object
    case Enum.find(mappings, fn mapping ->
      # Make sure to convert to string for comparison since JSON numbers become integers
      to_string(mapping["tautulliUserId"]) == to_string(tautulli_user_id)
    end) do
      # If we have a user object with jellyfin_id, use that
      %{"user" => %User{} = user} when not is_nil(user.jellyfin_id) ->
        {:ok, user, user.jellyfin_id}

      # If we have a jellyfinUserId but no User object was loaded, try to query it directly
      %{"jellyfinUserId" => user_id} ->
        case Repo.get(User, user_id) do
          %User{} = user when not is_nil(user.jellyfin_id) ->
            {:ok, user, user.jellyfin_id}
          _ ->
            {:skip, "User with ID #{user_id} not found or has no jellyfin_id"}
        end

      # If no mapping found, skip this record
      _ ->
        {:skip, "No user mapping found for Tautulli user ID: #{tautulli_user_id}"}
    end
  end

  defp get_user_and_jellyfin_id(tautulli_user_id, _) do
    {:skip, "No user mappings provided, skipping Tautulli user ID: #{tautulli_user_id}"}
  end

  # Generate a fallback device ID when none is provided
  defp generate_fallback_device_id(record) do
    # Create a consistent ID based on platform or player
    base = record["platform"] || record["player"] || "unknown"
    "tautulli_import_#{base}"
  end

  defp find_existing_session(server_id, item_id, user_id, start_time) do
    # Logic to find an existing session with matching criteria
    # This is to avoid duplicates during reimport
    Repo.get_by(PlaybackSession,
      server_id: server_id,
      item_jellyfin_id: item_id,
      user_jellyfin_id: user_id,
      start_time: start_time
    )
  end

  defp parse_tautulli_date(nil), do: nil

  defp parse_tautulli_date(timestamp) when is_integer(timestamp) do
    DateTime.from_unix!(timestamp)
  end

  defp parse_tautulli_date(timestamp) when is_binary(timestamp) do
    timestamp
    |> String.to_integer()
    |> DateTime.from_unix!()
  end

  defp map_transcode_decision("direct play"), do: "direct"
  defp map_transcode_decision("transcode"), do: "transcode"
  defp map_transcode_decision("direct stream"), do: "directstream"
  defp map_transcode_decision(_), do: "unknown"
end
