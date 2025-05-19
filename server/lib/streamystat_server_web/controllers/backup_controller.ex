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
    case Exqlite.Sqlite3.execute(db, "SELECT name FROM sqlite_master WHERE type='table' AND name LIKE '%playback_sessions%'") do
      {:ok, []} -> {:error, "No playback sessions table found in database"}
      {:ok, [[table_name]]} -> {:ok, table_name}
      error -> error
    end
  end

  defp fetch_all_rows(db, stmt) do
    rows = []
    case Exqlite.Sqlite3.step(db, stmt) do
      {:row, row} -> fetch_all_rows(db, stmt, [row | rows])
      :done -> Enum.reverse(rows)
      error -> error
    end
  end

  defp fetch_all_rows(db, stmt, rows) do
    case Exqlite.Sqlite3.step(db, stmt) do
      {:row, row} -> fetch_all_rows(db, stmt, [row | rows])
      :done -> Enum.reverse(rows)
      error -> error
    end
  end

  defp cleanup_db_resources(db, stmt) do
    :ok = Exqlite.Sqlite3.release(db, stmt)
    :ok = Exqlite.Sqlite3.close(db)
  end

  defp process_import_batches(rows, cols, server_id) do
    # Convert column names to atoms for easier access
    col_atoms = Enum.map(cols, &String.to_atom/1)

    # Process rows in batches
    rows
    |> Enum.chunk_every(@batch_size)
    |> Enum.reduce_while({:ok, 0}, fn batch, {:ok, count} ->
      case process_batch(batch, col_atoms, server_id) do
        {:ok, batch_count} -> {:cont, {:ok, count + batch_count}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp process_batch(rows, col_atoms, server_id) do
    # Convert rows to maps with atom keys
    sessions = Enum.map(rows, fn row ->
      Enum.zip(col_atoms, row) |> Map.new()
    end)

    # Insert sessions in a transaction
    case Repo.transaction(fn ->
      Enum.reduce_while(sessions, {:ok, 0}, fn session, {:ok, count} ->
        case create_session(session, server_id) do
          {:ok, _} -> {:cont, {:ok, count + 1}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)
    end) do
      {:ok, {:ok, count}} -> {:ok, count}
      {:ok, {:error, reason}} -> {:error, reason}
      {:error, reason} -> {:error, reason}
    end
  end

  defp create_session(session, server_id) do
    # Convert string timestamps to DateTime
    start_time = parse_datetime(session.start_time)
    end_time = parse_datetime(session.end_time)
    inserted_at = parse_datetime(session.inserted_at)
    updated_at = parse_datetime(session.updated_at)

    # Create session with converted timestamps
    %PlaybackSession{}
    |> PlaybackSession.changeset(%{
      id: session.id,
      user_jellyfin_id: session.user_jellyfin_id,
      device_id: session.device_id,
      device_name: session.device_name,
      client_name: session.client_name,
      item_jellyfin_id: session.item_jellyfin_id,
      item_name: session.item_name,
      series_jellyfin_id: session.series_jellyfin_id,
      series_name: session.series_name,
      season_jellyfin_id: session.season_jellyfin_id,
      play_duration: session.play_duration,
      play_method: session.play_method,
      start_time: start_time,
      end_time: end_time,
      position_ticks: session.position_ticks,
      runtime_ticks: session.runtime_ticks,
      percent_complete: session.percent_complete,
      completed: parse_bool(session.completed),
      server_id: server_id,
      inserted_at: inserted_at,
      updated_at: updated_at
    })
    |> Repo.insert()
  end

  defp parse_datetime(nil), do: nil
  defp parse_datetime(datetime_str) when is_binary(datetime_str) do
    case DateTime.from_iso8601(datetime_str) do
      {:ok, datetime, _} -> datetime
      _ -> nil
    end
  end
  defp parse_datetime(_), do: nil

  defp parse_bool(val) when val in [true, 1, "1", "t", "true", "TRUE"], do: true
  defp parse_bool(val) when val in [false, 0, "0", "f", "false", "FALSE"], do: false
  defp parse_bool(_), do: false

  defp cleanup_resources(db, stmt, temp_path) do
    if db do
      :ok = Exqlite.Sqlite3.close(db)
    end
    if stmt do
      :ok = Exqlite.Sqlite3.release(db, stmt)
    end
    if temp_path do
      File.rm(temp_path)
    end
  end
end
