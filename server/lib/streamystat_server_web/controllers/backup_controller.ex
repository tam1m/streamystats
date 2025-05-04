defmodule StreamystatServerWeb.BackupController do
  import Ecto.Query
  use StreamystatServerWeb, :controller
  alias StreamystatServer.Sessions.Models.PlaybackSession
  alias StreamystatServer.Servers.Models.Server
  alias StreamystatServer.Repo
  require Logger

  def export(conn, %{"server_id" => server_id_str}) do
    server_id = String.to_integer(server_id_str)
    {:ok, temp_path} = Temp.path(%{suffix: ".db"})
    {:ok, db} = Exqlite.Sqlite3.open(temp_path)

    # Use execute/2 for creating the table
    :ok =
      Exqlite.Sqlite3.execute(db, """
      CREATE TABLE playback_sessions (
        id INTEGER PRIMARY KEY,
        user_jellyfin_id TEXT NOT NULL,
        device_id TEXT,
        device_name TEXT,
        client_name TEXT,
        item_jellyfin_id TEXT NOT NULL,
        item_name TEXT,
        series_jellyfin_id TEXT,
        series_name TEXT,
        season_jellyfin_id TEXT,
        play_duration INTEGER NOT NULL,
        play_method TEXT,
        start_time TEXT NOT NULL,
        end_time TEXT,
        position_ticks INTEGER,
        runtime_ticks INTEGER,
        percent_complete REAL,
        completed BOOLEAN,
        server_id INTEGER NOT NULL,
        inserted_at TEXT,
        updated_at TEXT
      );
      """)

    # Prepare the insert statement
    {:ok, stmt} =
      Exqlite.Sqlite3.prepare(
        db,
        "INSERT INTO playback_sessions VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
      )

    # Increase timeout for large exports
    Repo.transaction(fn ->
      from(p in PlaybackSession, where: p.server_id == ^server_id)
      |> Repo.stream()
      |> Stream.each(fn s ->
        # Note: Ecto fetches timestamps as NaiveDateTime by default
        # Ensure they are converted to string format compatible with SQLite TEXT
        start_time_str = s.start_time |> DateTime.to_naive() |> NaiveDateTime.to_iso8601()

        end_time_str =
          if s.end_time,
            do: s.end_time |> DateTime.to_naive() |> NaiveDateTime.to_iso8601(),
            else: nil

        inserted_at_str = s.inserted_at |> NaiveDateTime.to_iso8601()
        updated_at_str = s.updated_at |> NaiveDateTime.to_iso8601()

        :ok =
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

    # Release the prepared statement
    :ok = Exqlite.Sqlite3.release(db, stmt)
    :ok = Exqlite.Sqlite3.close(db)

    server = Repo.get(Server, server_id)
    filename = "playback_sessions_#{server.name}_#{Date.utc_today()}.db"

    conn =
      conn
      |> put_resp_content_type("application/octet-stream")
      |> put_resp_header("content-disposition", "attachment; filename=#{filename}")
      |> send_file(200, temp_path)

    # Schedule file deletion after response is sent
    Task.start(fn ->
      Process.sleep(10_000)
      File.rm(temp_path)
    end)

    conn
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
      {:ok, db} = Exqlite.Sqlite3.open(file_path, mode: :readonly)
      {:ok, stmt} = Exqlite.Sqlite3.prepare(db, "SELECT * FROM playback_sessions")
      {:ok, cols} = Exqlite.Sqlite3.columns(db, stmt)

      col_atoms = Enum.map(cols, &String.to_existing_atom/1)

      rows =
        Stream.unfold(stmt, fn stmt ->
          case Exqlite.Sqlite3.step(db, stmt) do
            {:row, row} -> {row, stmt}
            :done -> nil
          end
        end)
        |> Enum.to_list()

      :ok = Exqlite.Sqlite3.release(db, stmt)
      :ok = Exqlite.Sqlite3.close(db)

      entries =
        rows
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

      {:ok, inserted_count}
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
      # id:              Map.get(attrs, :id), # Let DB generate ID on insert
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
