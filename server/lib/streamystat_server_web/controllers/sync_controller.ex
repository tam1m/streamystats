defmodule StreamystatServerWeb.SyncController do
  use StreamystatServerWeb, :controller
  alias StreamystatServer.SyncTask

  def partial_sync(conn, %{"server_id" => server_id}) do
    Task.start(fn ->
      SyncTask.partial_sync(server_id)
    end)

    conn
    |> put_status(:accepted)
    |> json(%{message: "Partial sync task initiated for server #{server_id}"})
  end

  def full_sync(conn, %{"server_id" => server_id}) do
    Task.start(fn ->
      SyncTask.full_sync(server_id)
    end)

    conn
    |> put_status(:accepted)
    |> json(%{message: "Full sync task initiated for server #{server_id}"})
  end

  def sync_users(conn, %{"server_id" => server_id}) do
    Task.start(fn ->
      SyncTask.sync_users(server_id)
    end)

    conn
    |> put_status(:accepted)
    |> json(%{message: "Users sync task initiated for server #{server_id}"})
  end

  def sync_libraries(conn, %{"server_id" => server_id}) do
    Task.start(fn ->
      SyncTask.sync_libraries(server_id)
    end)

    conn
    |> put_status(:accepted)
    |> json(%{message: "Libraries sync task initiated for server #{server_id}"})
  end

  def sync_items(conn, %{"server_id" => server_id}) do
    Task.start(fn ->
      SyncTask.sync_items(server_id)
    end)

    conn
    |> put_status(:accepted)
    |> json(%{message: "Items sync task initiated for server #{server_id}"})
  end

  def sync_playback_stats(conn, %{"server_id" => server_id}) do
    Task.start(fn ->
      SyncTask.sync_playback_stats(server_id)
    end)

    conn
    |> put_status(:accepted)
    |> json(%{message: "Playback stats sync task initiated for server #{server_id}"})
  end
end
