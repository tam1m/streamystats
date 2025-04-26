defmodule StreamystatServerWeb.SyncController do
  use StreamystatServerWeb, :controller
  alias StreamystatServer.Workers.SyncTask
  alias StreamystatServer.Servers.SyncLog
  alias StreamystatServer.Repo
  import Ecto.Query

  def full_sync(conn, %{"server_id" => server_id}) do
    Task.start(fn ->
      SyncTask.full_sync(server_id)
    end)

    conn
    |> put_status(:accepted)
    |> json(%{message: "Full sync task initiated for server #{server_id}"})
  end

  def sync_recently_added_items(conn, %{"server_id" => server_id}) do
    Task.start(fn ->
      SyncTask.sync_recently_added_items(server_id)
    end)

    conn
    |> put_status(:accepted)
    |> json(%{message: "Recently added items sync task initiated for server #{server_id}"})
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

  @spec list_tasks(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def list_tasks(conn, %{"server_id" => server_id}) do
    tasks_query =
      from(s in SyncLog,
        where: s.server_id == ^server_id and not is_nil(s.sync_started_at),
        order_by: [desc: s.sync_started_at],
        select: %{
          sync_type: s.sync_type,
          id: s.id,
          sync_started_at: s.sync_started_at,
          sync_completed_at: s.sync_completed_at,
          status: s.status
        },
        distinct: [s.sync_type],
        limit: 2
      )

    tasks =
      Repo.all(tasks_query)
      |> Enum.group_by(& &1.sync_type)
      |> Enum.flat_map(fn {_type, tasks} -> tasks end)
      |> Enum.sort_by(& &1.sync_started_at, {:desc, NaiveDateTime})

    conn
    |> put_status(:ok)
    |> render(:tasks, tasks: tasks)
  end

  def show_task(conn, %{"server_id" => server_id, "task_id" => task_id}) do
    case Repo.get_by(SyncLog, id: task_id, server_id: server_id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Task not found"})

      task ->
        conn
        |> put_status(:ok)
        |> render("task.json", task: task)
    end
  end
end
