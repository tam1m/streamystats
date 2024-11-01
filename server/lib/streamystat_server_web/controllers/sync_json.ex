defmodule StreamystatServerWeb.SyncJSON do
  alias StreamystatServer.Servers.SyncLog

  def tasks(%{tasks: tasks}) do
    %{data: for(task <- tasks, do: data(task))}
  end

  def task(%{task: task}) do
    %{data: data(task)}
  end

  defp data(%SyncLog{} = task) do
    data(Map.from_struct(task))
  end

  defp data(%{} = task) do
    %{
      id: task.id,
      server_id: Map.get(task, :server_id),
      sync_type: task.sync_type,
      sync_started_at: task.sync_started_at,
      sync_completed_at: task.sync_completed_at,
      status: task.status
    }
  end
end
