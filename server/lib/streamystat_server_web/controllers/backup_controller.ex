defmodule StreamystatServerWeb.BackupController do
  import Ecto.Query
  use StreamystatServerWeb, :controller
  alias StreamystatServer.Sessions.Models.PlaybackSession
  alias StreamystatServer.Servers.Models.Server
  alias StreamystatServer.Jellyfin.Models.User
  alias StreamystatServer.Repo
  require Logger

  # Set the amount of operations per batch
  @batch_size 1000
  # Default to 512KB cache size for low-resource systems
  @default_cache_size -512
  # Minimum memory threshold in MB to use memory storage
  @memory_storage_threshold 256

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
      completed, server_id, inserted_at, updated_at
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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

  defp bind_session_to_statement(stmt, session) do
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
    with :ok <- verify_file_exists(file_path),
         {:ok, db} <- Exqlite.Sqlite3.open(file_path, mode: :readonly),
         {:ok, table_name} <- find_playback_sessions_table(db),
         {:ok, stmt} <- Exqlite.Sqlite3.prepare(db, "SELECT * FROM #{table_name}"),
         {:ok, cols} <- Exqlite.Sqlite3.columns(db, stmt),
         rows <- fetch_all_rows(db, stmt),
         :ok <- cleanup_db_resources(db, stmt) do

      process_import_batches(rows, cols, server_id)
    else
      {:error, reason} -> {:error, reason}
      e -> {:error, "Import failed: #{Exception.message(e)}"}
    end
  end

  defp verify_file_exists(file_path) do
    if File.exists?(file_path), do: :ok, else: {:error, "Database file not found: #{file_path}"}
  end

  defp find_playback_sessions_table(db) do
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

        case Enum.find(tables, fn [table_name] ->
          String.downcase(table_name) == "playback_sessions"
        end) do
          [table_name] -> {:ok, table_name}
          nil -> {:error, "Invalid backup file: missing playback_sessions table"}
        end

      {:error, reason} ->
        {:error, "Failed to list database tables: #{reason}"}
    end
  end

  defp fetch_all_rows(db, stmt) do
    Stream.unfold(stmt, fn stmt ->
      case Exqlite.Sqlite3.step(db, stmt) do
        {:row, row} -> {row, stmt}
        :done -> nil
      end
    end)
    |> Enum.to_list()
  end

  defp cleanup_db_resources(db, stmt) do
    _ = Exqlite.Sqlite3.release(db, stmt)
    _ = Exqlite.Sqlite3.close(db)
    :ok
  end

  defp process_import_batches(rows, cols, server_id) do
    col_atoms = Enum.map(cols, &String.to_existing_atom/1)

    # Preload all users for this server to avoid N+1 queries
    users_map = Repo.all(from u in User, where: u.server_id == ^server_id)
    |> Enum.map(fn user -> {user.jellyfin_id, user} end)
    |> Map.new()

    total_inserted = rows
    |> Enum.chunk_every(@batch_size)
    |> Enum.reduce(0, fn batch, acc ->
      entries = batch
      |> Stream.map(fn row ->
        attrs = col_atoms
        |> Enum.zip(row)
        |> Map.new()
        |> Map.put(:server_id, server_id)

        # Get the user from our preloaded map
        user = Map.get(users_map, attrs[:user_jellyfin_id])

        # Add the user_id if we found a matching user
        attrs = if user do
          Map.put(attrs, :user_id, user.id)
        else
          attrs
        end

        format_attrs(attrs)
      end)
      |> Enum.to_list()

      {inserted_count, _} = Repo.insert_all(
        PlaybackSession,
        entries,
        on_conflict: :nothing,
        conflict_target: [:item_jellyfin_id, :user_jellyfin_id, :start_time, :server_id]
      )

      acc + inserted_count
    end)

    {:ok, total_inserted}
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
  end

  defp cleanup_resources(db, stmt, temp_path) do
    if db, do: :ok = Exqlite.Sqlite3.release(db, stmt)
    if db, do: :ok = Exqlite.Sqlite3.close(db)
    if temp_path, do: File.rm(temp_path)
  end

  defp parse_bool(val) when val in [true, 1, "1", "t", "true", "TRUE"], do: true
  defp parse_bool(val) when val in [false, 0, "0", "f", "false", "FALSE"], do: false
  # Default to nil if unsure
  defp parse_bool(_), do: nil

  defp format_attrs(attrs) do
    # Use Map.get for optional fields to avoid KeyError if column is missing in older backups
    %{
      user_id: Map.get(attrs, :user_id),
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

  defp parse_bool(val) when val in [true, 1, "1", "t", "true", "TRUE"], do: true
  defp parse_bool(val) when val in [false, 0, "0", "f", "false", "FALSE"], do: false
  defp parse_bool(_), do: nil

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
