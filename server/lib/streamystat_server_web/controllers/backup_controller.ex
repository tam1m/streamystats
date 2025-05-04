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

  defp configure_sqlite(db) do
    # Get system memory info using Erlang's built-in memory function
    total_memory = :erlang.memory(:total) / (1024 * 1024)  # Convert to MB

    # Configure cache size based on available memory
    cache_size =
      cond do
        total_memory > 1024 -> -2000  # 2MB for systems with >1GB RAM
        total_memory > 512 -> -1024   # 1MB for systems with >512MB RAM
        true -> @default_cache_size   # 512KB for low-memory systems
      end

    # Configure SQLite for better performance while being resource-friendly
    :ok = Exqlite.Sqlite3.execute(db, "PRAGMA journal_mode = WAL")  # Use WAL for better concurrency
    :ok = Exqlite.Sqlite3.execute(db, "PRAGMA synchronous = NORMAL") # Safer than OFF
    :ok = Exqlite.Sqlite3.execute(db, "PRAGMA cache_size = #{cache_size}")

    # Only use memory storage if we have enough RAM
    if total_memory > @memory_storage_threshold do
      :ok = Exqlite.Sqlite3.execute(db, "PRAGMA temp_store = MEMORY")
    else
      :ok = Exqlite.Sqlite3.execute(db, "PRAGMA temp_store = FILE")
    end

    # Set page size to 4KB (default) for better compatibility
    :ok = Exqlite.Sqlite3.execute(db, "PRAGMA page_size = 4096")
  end

  def export(conn, %{"server_id" => server_id_str}) do
    server_id = String.to_integer(server_id_str)

    # Create a temporary file for the SQLite database
    temp_path = Path.join(System.tmp_dir!(), "playback_sessions_#{:rand.uniform(1000000)}.db")
    {:ok, db} = Exqlite.Sqlite3.open(temp_path)

    # Configure SQLite with adaptive settings
    configure_sqlite(db)

    # Create the table in the SQLite database
    :ok =
      Exqlite.Sqlite3.execute(db, """
      CREATE TABLE playback_sessions (
        id INTEGER PRIMARY KEY,
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
        inserted_at TEXT,
        updated_at TEXT
      )
      """)

    # Prepare the insert statement
    {:ok, stmt} =
      Exqlite.Sqlite3.prepare(db, """
      INSERT INTO playback_sessions (
        id, user_jellyfin_id, device_id, device_name, client_name,
        item_jellyfin_id, item_name, series_jellyfin_id, series_name,
        season_jellyfin_id, play_duration, play_method, start_time,
        end_time, position_ticks, runtime_ticks, percent_complete,
        completed, server_id, inserted_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      """)

    try do
      # Process in batches using Repo.stream within a transaction
      Repo.transaction(fn ->
        from(s in PlaybackSession, where: s.server_id == ^server_id)
        |> Repo.stream()
        |> Stream.each(fn s ->
          start_time_str = if s.start_time, do: DateTime.to_iso8601(s.start_time), else: nil
          end_time_str = if s.end_time, do: DateTime.to_iso8601(s.end_time), else: nil
          inserted_at_str = NaiveDateTime.to_iso8601(s.inserted_at)
          updated_at_str = NaiveDateTime.to_iso8601(s.updated_at)

          Exqlite.Sqlite3.bind(stmt, [
            s.id,
            s.user_jellyfin_id,
            s.device_id,
            s.device_name,
            s.client_name,
            s.item_jellyfin_id,
            s.item_name,
            s.series_jellyfin_id,
            s.series_name,
            s.season_jellyfin_id,
            s.play_duration,
            s.play_method,
            start_time_str,
            end_time_str,
            s.position_ticks,
            s.runtime_ticks,
            s.percent_complete,
            s.completed,
            s.server_id,
            inserted_at_str,
            updated_at_str
          ])

          :done = Exqlite.Sqlite3.step(db, stmt)
          :ok = Exqlite.Sqlite3.reset(stmt)
        end)
        |> Stream.run()
      end, timeout: 300_000) # 5 minutes

      server = Repo.get(Server, server_id)
      filename = "playback_sessions_#{server.name}_#{Date.utc_today()}.db"

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
    rescue
      e ->
        # Clean up resources
        :ok = Exqlite.Sqlite3.release(db, stmt)
        :ok = Exqlite.Sqlite3.close(db)
        File.rm(temp_path)

        # Log the error
        Logger.error("Export failed: #{inspect(e)}")

        # Return error response
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Failed to export playback sessions"})
    end
  end

  def import(conn, %{"server_id" => server_id_str, "file" => %Plug.Upload{path: path}}) do
    server_id = String.to_integer(server_id_str)

    case Repo.get(Server, server_id) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "Server not found"})

      _ ->
        case process_import(path, server_id) do
          {:ok, count} ->
            json(conn, %{message: "Successfully imported #{count} playback sessions"})

          {:error, reason} ->
            conn |> put_status(:bad_request) |> json(%{error: reason})
        end
    end
  end

  defp process_import(file_path, server_id) do
    try do
      # Verify the file exists and is readable
      unless File.exists?(file_path) do
        raise "Database file not found: #{file_path}"
      end

      # Verify the file is a valid SQLite database
      case Exqlite.Sqlite3.open(file_path, mode: :readonly) do
        {:ok, db} ->
          try do
            # List all tables in the database
            case Exqlite.Sqlite3.prepare(db, "SELECT name FROM sqlite_master WHERE type='table'") do
              {:ok, stmt} ->
                tables = Stream.unfold(stmt, fn stmt ->
                  case Exqlite.Sqlite3.step(db, stmt) do
                    {:row, row} -> {row, stmt}
                    :done -> nil
                  end
                end)
                |> Enum.to_list()

                _ = Exqlite.Sqlite3.release(db, stmt)

                # Check if playback_sessions table exists (case-insensitive)
                case Enum.find(tables, fn [table_name] ->
                  String.downcase(table_name) == "playback_sessions"
                end) do
                  [table_name] ->
                    case Exqlite.Sqlite3.prepare(db, "SELECT * FROM #{table_name}") do
                      {:ok, stmt} ->
                        case Exqlite.Sqlite3.columns(db, stmt) do
                          {:ok, cols} ->
                            col_atoms = Enum.map(cols, &String.to_existing_atom/1)

                            rows =
                              Stream.unfold(stmt, fn stmt ->
                                case Exqlite.Sqlite3.step(db, stmt) do
                                  {:row, row} -> {row, stmt}
                                  :done -> nil
                                end
                              end)
                              |> Enum.to_list()

                            # Release statement and close database
                            _ = Exqlite.Sqlite3.release(db, stmt)
                            _ = Exqlite.Sqlite3.close(db)

                            # Process rows in batches of 1000 to avoid exceeding PostgreSQL's parameter limit
                            batch_size = 1000

                            total_inserted = rows
                            |> Enum.chunk_every(batch_size)
                            |> Enum.reduce(0, fn batch, acc ->
                              entries =
                                batch
                                |> Stream.map(fn row ->
                                  col_atoms
                                  |> Enum.zip(row)
                                  |> Map.new()
                                  # Ensure the correct server_id is used
                                  |> Map.put(:server_id, server_id)
                                  |> format_attrs()
                                end)
                                |> Enum.to_list()

                              # bulk‐insert, skipping any conflicts
                              {inserted_count, _} =
                                Repo.insert_all(
                                  PlaybackSession,
                                  entries,
                                  on_conflict: :nothing,
                                  conflict_target: [:item_jellyfin_id, :user_jellyfin_id, :start_time, :server_id]
                                )

                              acc + inserted_count
                            end)

                            {:ok, total_inserted}

                          {:error, reason} ->
                            _ = Exqlite.Sqlite3.release(db, stmt)
                            _ = Exqlite.Sqlite3.close(db)
                            Logger.error("Failed to get columns: #{inspect(reason)}")
                            {:error, "Failed to get table columns: #{reason}"}
                        end

                      {:error, reason} ->
                        _ = Exqlite.Sqlite3.close(db)
                        Logger.error("Failed to prepare statement: #{inspect(reason)}")
                        {:error, "Failed to prepare SQL statement: #{reason}"}
                    end

                  nil ->
                    _ = Exqlite.Sqlite3.close(db)
                    Logger.error("No playback_sessions table found in database")
                    {:error, "Invalid backup file: missing playback_sessions table"}
                end

              {:error, reason} ->
                _ = Exqlite.Sqlite3.close(db)
                Logger.error("Failed to prepare table list statement: #{inspect(reason)}")
                {:error, "Failed to list database tables: #{reason}"}
            end
          rescue
            e ->
              _ = Exqlite.Sqlite3.close(db)
              Logger.error("Error processing database: #{inspect(e)}")
              raise e
          end

        {:error, reason} ->
          Logger.error("Failed to open database: #{inspect(reason)}")
          {:error, "Invalid database file: #{reason}"}
      end
    rescue
      # Fix the error type references
      e in Postgrex.Error ->
        Logger.error("Database error during import: #{inspect(e)}")
        {:error, "Database error during import: #{Exception.message(e)}"}

      e in DBConnection.ConnectionError ->
        Logger.error("Database connection error during import: #{inspect(e)}")
        {:error, "Database connection error: #{Exception.message(e)}"}

      e in Ecto.ChangeError ->
        Logger.error("Ecto change error during import: #{inspect(e)}")
        {:error, "Database change error: #{Exception.message(e)}"}

      e ->
        Logger.error("Import error: #{inspect(e)}")
        {:error, "Failed to process import file: #{Exception.message(e)}"}
    end
  end

  defp parse_bool(val) when val in [true, 1, "1", "t", "true", "TRUE"], do: true
  defp parse_bool(val) when val in [false, 0, "0", "f", "false", "FALSE"], do: false
  # Default to nil if unsure
  defp parse_bool(_), do: nil

  defp format_attrs(attrs) do
    # Use Map.get for optional fields to avoid KeyError if column is missing in older backups
    %{
      user_jellyfin_id: Map.get(attrs, :user_jellyfin_id),
      device_id: Map.get(attrs, :device_id),
      device_name: Map.get(attrs, :device_name),
      client_name: Map.get(attrs, :client_name),
      item_jellyfin_id: Map.get(attrs, :item_jellyfin_id),
      item_name: Map.get(attrs, :item_name),
      series_jellyfin_id: Map.get(attrs, :series_jellyfin_id),
      series_name: Map.get(attrs, :series_name),
      season_jellyfin_id: Map.get(attrs, :season_jellyfin_id),
      play_duration: Map.get(attrs, :play_duration),
      play_method: Map.get(attrs, :play_method),
      # Expects DateTime or nil
      start_time: parse_utc(Map.get(attrs, :start_time)),
      # Expects DateTime or nil
      end_time: parse_utc(Map.get(attrs, :end_time)),
      position_ticks: Map.get(attrs, :position_ticks),
      runtime_ticks: Map.get(attrs, :runtime_ticks),
      percent_complete: Map.get(attrs, :percent_complete),
      completed: parse_bool(Map.get(attrs, :completed)),
      # Already set in process_import, but Map.get won't hurt
      server_id: Map.get(attrs, :server_id),
      # Generate new timestamps for the import, truncated to seconds
      inserted_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second),
      updated_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
    }
    # Drop the old ID from the backup file
    |> Map.drop([:id])
  end

  defp parse_utc(nil), do: nil

  defp parse_utc(iso8601_string) when is_binary(iso8601_string) do
    with {:ok, naive_dt} <- NaiveDateTime.from_iso8601(iso8601_string),
         # Assume the string from SQLite is UTC, convert to DateTime
         {:ok, datetime} <- DateTime.from_naive(naive_dt, "Etc/UTC") do
      # Return the DateTime struct directly
      datetime
    else
      # Handle errors from either from_iso8601 or from_naive
      {:error, _reason} ->
        Logger.warning("Failed to parse timestamp from backup: #{iso8601_string}")
        nil

      # Handle cases where the input wasn't a binary string (though guard should prevent)
      _non_binary_or_error ->
        Logger.warning("Unexpected input or error parsing timestamp: #{inspect(iso8601_string)}")
        nil
    end
  rescue
    # Catch potential errors during conversion (e.g., invalid format)
    e ->
      Logger.error("Error parsing timestamp '#{iso8601_string}': #{inspect(e)}")
      nil
  end

  # Handle non-string inputs gracefully
  defp parse_utc(_other), do: nil
end
