defmodule StreamystatServerWeb.BackupController do
  import Ecto.Query
  use StreamystatServerWeb, :controller
  alias StreamystatServer.Sessions.Models.PlaybackSession
  alias StreamystatServer.Servers.Models.Server
  alias StreamystatServer.Repo
  require Logger

  # Default to 512KB cache size for low-resource systems
  @default_cache_size -512
  # Minimum memory threshold in MB to use memory storage
  @memory_storage_threshold 256

  # Import function to handle backup restoration
  def import(conn, %{"server_id" => server_id_str} = params) do
    server_id = String.to_integer(server_id_str)

    # Verify the server exists
    unless Repo.exists?(from s in Server, where: s.id == ^server_id) do
      Logger.error("Import failed: Server ID #{server_id} not found")
      conn |> put_status(:not_found) |> json(%{error: "Server not found"})
    else
      Logger.info("Starting backup import for server ID: #{server_id}")

      # Process uploaded file
      case conn.body_params do
        %{"file" => %Plug.Upload{path: temp_path, filename: filename}} ->
          if not String.ends_with?(filename, ".db") do
            Logger.error("Import failed: Invalid file type (#{filename})")
            conn |> put_status(:bad_request) |> json(%{error: "Invalid file type. Please upload a .db file."})
          else
            db = nil

            try do
              # Open the SQLite database
              {:ok, db} = Exqlite.Sqlite3.open(temp_path)
              :ok = configure_sqlite(db)

              # Verify it has the expected table structure
              {:ok, validate_stmt} = Exqlite.Sqlite3.prepare(db, "SELECT name FROM sqlite_master WHERE type='table' AND name='playback_sessions'")
              table_exists = case Exqlite.Sqlite3.step(db, validate_stmt) do
                {:row, _} -> true
                :done -> false
              end
              :ok = Exqlite.Sqlite3.release(db, validate_stmt)

              if not table_exists do
                Logger.error("Import failed: Invalid database structure")
                conn |> put_status(:bad_request) |> json(%{error: "Invalid backup file. Missing required table structure."})
              else
                # Check the table schema to determine available columns
                {:ok, schema_stmt} = Exqlite.Sqlite3.prepare(db, "PRAGMA table_info(playback_sessions)")
                columns = Stream.unfold(db, fn db ->
                  case Exqlite.Sqlite3.step(db, schema_stmt) do
                    {:row, row} ->
                      # Column name is the second element in the row
                      {Enum.at(row, 1), db}
                    :done -> nil
                    error ->
                      Logger.error("Error reading schema: #{inspect(error)}")
                      nil
                  end
                end)
                |> Enum.to_list()

                :ok = Exqlite.Sqlite3.release(db, schema_stmt)

                Logger.info("Available columns in imported database: #{inspect(columns)}")

                # Build a SQL query based on available columns
                base_columns = [
                  "user_jellyfin_id", "device_id", "device_name", "client_name",
                  "item_jellyfin_id", "item_name", "series_jellyfin_id", "series_name",
                  "season_jellyfin_id", "play_duration", "play_method", "start_time",
                  "end_time", "position_ticks", "runtime_ticks", "percent_complete",
                  "completed"
                ]

                # Optional columns that might not exist in older backups
                optional_columns = [
                  "is_paused", "is_muted", "volume_level",
                  "audio_stream_index", "subtitle_stream_index", "media_source_id",
                  "repeat_mode", "playback_order", "remote_end_point", "session_id",
                  "user_name", "last_activity_date", "last_playback_check_in",
                  "application_version", "is_active", "transcoding_audio_codec",
                  "transcoding_video_codec", "transcoding_container",
                  "transcoding_is_video_direct", "transcoding_is_audio_direct",
                  "transcoding_bitrate", "transcoding_completion_percentage",
                  "transcoding_width", "transcoding_height", "transcoding_audio_channels",
                  "transcoding_hardware_acceleration_type", "transcoding_reasons",
                  "inserted_at", "updated_at"
                ]

                # Filter optional columns to only include those that exist in the DB
                available_optional_columns = Enum.filter(optional_columns, fn col -> col in columns end)

                # Combine base and available optional columns
                select_columns = base_columns ++ available_optional_columns
                select_sql = "SELECT #{Enum.join(select_columns, ", ")} FROM playback_sessions"

                Logger.info("Using SQL query: #{select_sql}")

                # Process records one by one instead of in a large transaction
                {:ok, select_stmt} = Exqlite.Sqlite3.prepare(db, select_sql)

                # Read all sessions from the SQLite database and process them one by one
                session_count = 0
                imported_count = 0
                # Create counters with size 1 (not 0-based but 1-based in Erlang)
                session_count_ref = :counters.new(1, [])
                imported_count_ref = :counters.new(1, [])

                # Create a copy of the database path for the background process
                temp_path_copy = Path.dirname(temp_path) <> "/" <> Path.basename(temp_path) <> ".copy"
                File.cp!(temp_path, temp_path_copy)

                # Start a background process to handle the import
                Task.start(fn ->
                  try do
                    # Process each row using recursion to avoid transaction issues
                    process_rows(db, select_stmt, select_columns, server_id, session_count_ref, imported_count_ref)

                    # Release statement
                    :ok = Exqlite.Sqlite3.release(db, select_stmt)

                    # Log the completion
                    total = :counters.get(session_count_ref, 1)
                    imported = :counters.get(imported_count_ref, 1)
                    Logger.info("Successfully imported #{imported} of #{total} sessions from backup")
                  rescue
                    e ->
                      Logger.error("Import process failed with error: #{inspect(e)}")
                  after
                    # Close the SQLite database
                    if db != nil do
                      case Exqlite.Sqlite3.close(db) do
                        :ok -> :ok
                        error -> Logger.error("Failed to close database: #{inspect(error)}")
                      end
                    end
                    # Clean up the temporary file copy
                    File.rm(temp_path_copy)
                  end
                end)

                # Immediately return a success response instead of waiting
                conn |> put_status(:accepted) |> json(%{
                  message: "Import started successfully. Sessions are being processed in the background.",
                  status: "processing"
                })
              end

            rescue
              e ->
                Logger.error("Import failed with error: #{inspect(e)}")
                conn |> put_status(:internal_server_error) |> json(%{error: "Error processing backup file"})
            after
              # Don't close the DB here since it's being used in the background process
              # We'll close it in the background task
            end
          end

        _ ->
          Logger.error("Import failed: No file uploaded")
          conn |> put_status(:bad_request) |> json(%{error: "No file uploaded"})
      end
    end
  end

  # Helper functions for import

  defp parse_datetime(datetime_str) when is_binary(datetime_str) do
    case DateTime.from_iso8601(datetime_str) do
      {:ok, datetime, _} -> datetime
      _ -> nil
    end
  end

  defp parse_datetime(_), do: nil

  defp parse_transcoding_reasons(reasons_json) when is_binary(reasons_json) do
    case Jason.decode(reasons_json) do
      {:ok, reasons} when is_list(reasons) -> reasons
      _ -> []
    end
  end

  defp parse_transcoding_reasons(_), do: []

  defp configure_sqlite(db) do
    # Get system memory info using Erlang's built-in memory function
    total_memory = :erlang.memory(:total) / (1024 * 1024)  # Convert to MB
    # Configure cache size based on available memory
    cache_size = get_cache_size(total_memory)

    # Configure SQLite for better performance while being resource-friendly
    :ok = Exqlite.Sqlite3.execute(db, "PRAGMA journal_mode = DELETE")  # Use DELETE instead of WAL
    :ok = Exqlite.Sqlite3.execute(db, "PRAGMA synchronous = NORMAL") # Safer than OFF
    :ok = Exqlite.Sqlite3.execute(db, "PRAGMA cache_size = #{cache_size}")
    # Only use memory storage if we have enough RAM
    :ok = Exqlite.Sqlite3.execute(db, "PRAGMA temp_store = #{if total_memory > @memory_storage_threshold, do: "MEMORY", else: "FILE"}")
    # Set page size to 4KB (default) for better compatibility
    :ok = Exqlite.Sqlite3.execute(db, "PRAGMA page_size = 4096")
    # Set busy timeout to 5 seconds
    :ok = Exqlite.Sqlite3.execute(db, "PRAGMA busy_timeout = 5000")
  end

  defp get_cache_size(total_memory) do
    cond do
      total_memory > 1024 -> -2000
      total_memory > 512 -> -1024
      true -> @default_cache_size
    end
  end

  def export(conn, %{"server_id" => server_id_str}) do
    server_id = String.to_integer(server_id_str)
    # Create a temporary file for the SQLite database
    temp_path = Temp.path!(".db")
    # Initialize db as nil; it will be assigned later and used in rescue/after blocks
    db = nil
    stmt = nil

    try do
      {:ok, db} = Exqlite.Sqlite3.open(temp_path)
      :ok = configure_sqlite(db)
      :ok = create_playback_sessions_table(db)
      {:ok, stmt} = prepare_insert_statement(db)

      # Start a transaction for better performance
      :ok = Exqlite.Sqlite3.execute(db, "BEGIN IMMEDIATE TRANSACTION")

      case export_sessions(db, stmt, server_id) do
        {:ok, _} ->
          # Verify data was written
          {:ok, verify_stmt} = Exqlite.Sqlite3.prepare(db, "SELECT COUNT(*) FROM playback_sessions")
          {:row, [written_count]} = Exqlite.Sqlite3.step(db, verify_stmt)
          :ok = Exqlite.Sqlite3.release(db, verify_stmt)

          Logger.info("Successfully wrote #{written_count} sessions to SQLite database")

          :ok = Exqlite.Sqlite3.execute(db, "COMMIT")

          # Close the database properly
          :ok = Exqlite.Sqlite3.close(db)
          db = nil

          server = Repo.get(Server, server_id)
          filename = "playback_sessions_#{server.name}_#{Date.utc_today()}.db"

          # Verify file exists and has content
          case File.stat(temp_path) do
            {:ok, %{size: size}} ->
              Logger.info("Database file size: #{size} bytes")
            {:error, reason} ->
              Logger.error("Failed to stat database file: #{inspect(reason)}")
              raise "Database file not found or inaccessible"
          end

          conn =
            conn
            |> put_resp_content_type("application/x-sqlite3")
            |> put_resp_header("content-disposition", "attachment; filename=#{filename}")
            |> send_file(200, temp_path)

          # Schedule file deletion after response is sent
          Task.start(fn ->
            Process.sleep(10_000)
            File.rm(temp_path)
          end)

          conn
        {:error, reason} ->
          Logger.error("Export failed: #{inspect(reason)}")
          :ok = Exqlite.Sqlite3.execute(db, "ROLLBACK")
          conn |> put_status(:internal_server_error) |> json(%{error: "Failed to export playback sessions"})
      end
    rescue
      e ->
        Logger.error("Export failed: #{inspect(e)}")
        # Rollback transaction if it exists
        if db do
          :ok = Exqlite.Sqlite3.execute(db, "ROLLBACK")
        end
        conn |> put_status(:internal_server_error) |> json(%{error: "Failed to export playback sessions"})
    after
      cleanup_resources(db, stmt, temp_path)
    end
  end

  defp create_playback_sessions_table(db) do
    case Exqlite.Sqlite3.execute(db, """
    CREATE TABLE playback_sessions (
      id TEXT PRIMARY KEY,
      user_jellyfin_id TEXT,
      device_id TEXT,
      device_name TEXT,
      client_name TEXT,
      item_jellyfin_id TEXT,
      item_name TEXT,
      series_jellyfin_id TEXT,
      series_name TEXT,
      season_jellyfin_id TEXT,
      play_duration INTEGER,
      play_method TEXT,
      start_time TEXT,
      end_time TEXT,
      position_ticks INTEGER,
      runtime_ticks INTEGER,
      percent_complete FLOAT,
      completed BOOLEAN,
      server_id INTEGER,
      is_paused BOOLEAN,
      is_muted BOOLEAN,
      volume_level INTEGER,
      audio_stream_index INTEGER,
      subtitle_stream_index INTEGER,
      media_source_id TEXT,
      repeat_mode TEXT,
      playback_order TEXT,
      remote_end_point TEXT,
      session_id TEXT,
      user_name TEXT,
      last_activity_date TEXT,
      last_playback_check_in TEXT,
      application_version TEXT,
      is_active BOOLEAN,
      transcoding_audio_codec TEXT,
      transcoding_video_codec TEXT,
      transcoding_container TEXT,
      transcoding_is_video_direct BOOLEAN,
      transcoding_is_audio_direct BOOLEAN,
      transcoding_bitrate INTEGER,
      transcoding_completion_percentage FLOAT,
      transcoding_width INTEGER,
      transcoding_height INTEGER,
      transcoding_audio_channels INTEGER,
      transcoding_hardware_acceleration_type TEXT,
      transcoding_reasons TEXT,
      inserted_at TEXT,
      updated_at TEXT
    )
    """) do
      {:ok, _} -> :ok
      :ok -> :ok
      error -> error
    end
  end

  defp prepare_insert_statement(db) do
    Exqlite.Sqlite3.prepare(db, """
    INSERT INTO playback_sessions (
      id, user_jellyfin_id, device_id, device_name, client_name,
      item_jellyfin_id, item_name, series_jellyfin_id, series_name,
      season_jellyfin_id, play_duration, play_method, start_time,
      end_time, position_ticks, runtime_ticks, percent_complete,
      completed, server_id, is_paused, is_muted, volume_level,
      audio_stream_index, subtitle_stream_index, media_source_id,
      repeat_mode, playback_order, remote_end_point, session_id,
      user_name, last_activity_date, last_playback_check_in,
      application_version, is_active, transcoding_audio_codec,
      transcoding_video_codec, transcoding_container,
      transcoding_is_video_direct, transcoding_is_audio_direct,
      transcoding_bitrate, transcoding_completion_percentage,
      transcoding_width, transcoding_height, transcoding_audio_channels,
      transcoding_hardware_acceleration_type, transcoding_reasons,
      inserted_at, updated_at
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    """)
  end

  defp export_sessions(db, stmt, server_id) do
    Repo.transaction(fn ->
      from(s in PlaybackSession, where: s.server_id == ^server_id)
      |> Repo.stream()
      |> Stream.each(fn s ->
        bind_session_to_statement(stmt, s)
        case Exqlite.Sqlite3.step(db, stmt) do
          :done -> :ok
          {:error, reason} ->
            Logger.error("Failed to write session #{s.id}: #{inspect(reason)}")
            raise "Failed to write session to SQLite"
        end
        :ok = Exqlite.Sqlite3.reset(stmt)
      end)
      |> Stream.run()
    end, timeout: 300_000)
  end

  defp cleanup_resources(db, stmt, temp_path) do
    # Release statement if available
    if db != nil && stmt != nil do
      case Exqlite.Sqlite3.release(db, stmt) do
        :ok -> :ok
        error -> Logger.error("Failed to release statement: #{inspect(error)}")
      end
    end

    # Close database if open
    if db != nil do
      case Exqlite.Sqlite3.close(db) do
        :ok -> :ok
        error -> Logger.error("Failed to close database: #{inspect(error)}")
      end
    end

    # Delete temp file if exists
    if temp_path != nil && File.exists?(temp_path) do
      case File.rm(temp_path) do
        :ok -> :ok
        {:error, reason} -> Logger.error("Failed to delete temp file: #{inspect(reason)}")
      end
    end
  end

  defp bind_session_to_statement(stmt, session) do
    # Handle transcoding_reasons to ensure it's exported as JSON string
    transcoding_reasons =
      if is_list(session.transcoding_reasons) do
        Jason.encode!(session.transcoding_reasons)
      else
        session.transcoding_reasons
      end

    values = [
      session.id,
      session.user_jellyfin_id,
      session.device_id,
      session.device_name,
      session.client_name,
      session.item_jellyfin_id,
      session.item_name,
      session.series_jellyfin_id,
      session.series_name,
      session.season_jellyfin_id,
      session.play_duration,
      session.play_method,
      if(session.start_time, do: DateTime.to_iso8601(session.start_time), else: nil),
      if(session.end_time, do: DateTime.to_iso8601(session.end_time), else: nil),
      session.position_ticks,
      session.runtime_ticks,
      session.percent_complete,
      session.completed,
      session.server_id,
      session.is_paused,
      session.is_muted,
      session.volume_level,
      session.audio_stream_index,
      session.subtitle_stream_index,
      session.media_source_id,
      session.repeat_mode,
      session.playback_order,
      session.remote_end_point,
      session.session_id,
      session.user_name,
      if(session.last_activity_date, do: DateTime.to_iso8601(session.last_activity_date), else: nil),
      if(session.last_playback_check_in, do: DateTime.to_iso8601(session.last_playback_check_in), else: nil),
      session.application_version,
      session.is_active,
      session.transcoding_audio_codec,
      session.transcoding_video_codec,
      session.transcoding_container,
      session.transcoding_is_video_direct,
      session.transcoding_is_audio_direct,
      session.transcoding_bitrate,
      session.transcoding_completion_percentage,
      session.transcoding_width,
      session.transcoding_height,
      session.transcoding_audio_channels,
      session.transcoding_hardware_acceleration_type,
      transcoding_reasons,
      NaiveDateTime.to_iso8601(session.inserted_at),
      NaiveDateTime.to_iso8601(session.updated_at)
    ]

    case Exqlite.Sqlite3.bind(stmt, values) do
      :ok -> :ok
      {:error, reason} ->
        Logger.error("Failed to bind session #{session.id}: #{inspect(reason)}")
        raise "Failed to bind session to SQLite statement"
    end
  end

  defp process_rows(db, stmt, columns, server_id, session_count_ref, imported_count_ref) do
    case Exqlite.Sqlite3.step(db, stmt) do
      {:row, row} ->
        # Create a map of column names to values
        values_map = Enum.zip(columns, row) |> Map.new()

        # Create a map of attributes for the new PlaybackSession with default values for missing columns
        attrs = %{
          user_jellyfin_id: Map.get(values_map, "user_jellyfin_id"),
          device_id: Map.get(values_map, "device_id"),
          device_name: Map.get(values_map, "device_name"),
          client_name: Map.get(values_map, "client_name"),
          item_jellyfin_id: Map.get(values_map, "item_jellyfin_id"),
          item_name: Map.get(values_map, "item_name"),
          series_jellyfin_id: Map.get(values_map, "series_jellyfin_id"),
          series_name: Map.get(values_map, "series_name"),
          season_jellyfin_id: Map.get(values_map, "season_jellyfin_id"),
          play_duration: Map.get(values_map, "play_duration"),
          play_method: Map.get(values_map, "play_method"),
          start_time: if(Map.get(values_map, "start_time"), do: parse_datetime(Map.get(values_map, "start_time")), else: nil),
          end_time: if(Map.get(values_map, "end_time"), do: parse_datetime(Map.get(values_map, "end_time")), else: nil),
          position_ticks: Map.get(values_map, "position_ticks"),
          runtime_ticks: Map.get(values_map, "runtime_ticks"),
          percent_complete: Map.get(values_map, "percent_complete"),
          completed: Map.get(values_map, "completed"),
          server_id: server_id,
          is_paused: Map.get(values_map, "is_paused"),
          is_muted: Map.get(values_map, "is_muted"),
          volume_level: Map.get(values_map, "volume_level"),
          audio_stream_index: Map.get(values_map, "audio_stream_index"),
          subtitle_stream_index: Map.get(values_map, "subtitle_stream_index"),
          media_source_id: Map.get(values_map, "media_source_id"),
          repeat_mode: Map.get(values_map, "repeat_mode"),
          playback_order: Map.get(values_map, "playback_order"),
          remote_end_point: Map.get(values_map, "remote_end_point"),
          session_id: Map.get(values_map, "session_id"),
          user_name: Map.get(values_map, "user_name"),
          last_activity_date: if(Map.get(values_map, "last_activity_date"), do: parse_datetime(Map.get(values_map, "last_activity_date")), else: nil),
          last_playback_check_in: if(Map.get(values_map, "last_playback_check_in"), do: parse_datetime(Map.get(values_map, "last_playback_check_in")), else: nil),
          application_version: Map.get(values_map, "application_version"),
          is_active: Map.get(values_map, "is_active"),
          transcoding_audio_codec: Map.get(values_map, "transcoding_audio_codec"),
          transcoding_video_codec: Map.get(values_map, "transcoding_video_codec"),
          transcoding_container: Map.get(values_map, "transcoding_container"),
          transcoding_is_video_direct: Map.get(values_map, "transcoding_is_video_direct"),
          transcoding_is_audio_direct: Map.get(values_map, "transcoding_is_audio_direct"),
          transcoding_bitrate: Map.get(values_map, "transcoding_bitrate"),
          transcoding_completion_percentage: Map.get(values_map, "transcoding_completion_percentage"),
          transcoding_width: Map.get(values_map, "transcoding_width"),
          transcoding_height: Map.get(values_map, "transcoding_height"),
          transcoding_audio_channels: Map.get(values_map, "transcoding_audio_channels"),
          transcoding_hardware_acceleration_type: Map.get(values_map, "transcoding_hardware_acceleration_type"),
          transcoding_reasons: parse_transcoding_reasons(Map.get(values_map, "transcoding_reasons"))
        }

        # Validate UUID format for user_jellyfin_id and item_jellyfin_id
        # This is important now that we've switched from IDs to UUIDs
        is_valid_uuid = fn str ->
          case str do
            nil -> false
            str when is_binary(str) ->
              # Only accept format without hyphens (32 hex characters)
              Regex.match?(~r/^[0-9a-f]{32}$/i, str)
            _ -> false
          end
        end

        # Try to import each session, catching any errors to prevent transaction abortion
        try do
          # Only proceed with valid UUIDs for critical fields
          if is_valid_uuid.(attrs.user_jellyfin_id) and is_valid_uuid.(attrs.item_jellyfin_id) do
            # Create and insert the PlaybackSession
            changeset = PlaybackSession.changeset(%PlaybackSession{}, attrs)

            # Insert using the changeset
            case Repo.insert(changeset, on_conflict: :nothing) do
              {:ok, session} ->
                :counters.add(imported_count_ref, 1, 1)
                1
              {:error, error} ->
                Logger.warning("Failed to import session: #{inspect(error)}")
                0
            end
          else
            Logger.warning("Skipping import of session with invalid UUID format: user_jellyfin_id=#{attrs.user_jellyfin_id}, item_jellyfin_id=#{attrs.item_jellyfin_id}")
            0
          end
        rescue
          e ->
            Logger.warning("Error processing session: #{inspect(e)}")
            0
        end

        # Increment counters
        :counters.add(session_count_ref, 1, 1)

        # Process next row recursively
        process_rows(db, stmt, columns, server_id, session_count_ref, imported_count_ref)

      :done ->
        :ok

      error ->
        Logger.error("Error processing row: #{inspect(error)}")
        :ok
    end
  end
end
