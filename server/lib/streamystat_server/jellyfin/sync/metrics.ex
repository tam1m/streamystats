defmodule StreamystatServer.Jellyfin.Sync.Metrics do
  @moduledoc """
  Handles metrics tracking for sync operations.
  """

  require Logger

  @doc """
  Creates a new metrics agent with the given initial metrics.
  """
  def start_agent(initial_metrics \\ %{}) do
    Agent.start_link(fn -> initial_metrics end)
  end

  @doc """
  Updates metrics in the metrics agent.
  If agent is nil, does nothing.
  """
  def update(nil, _updates), do: :ok

  def update(agent, updates) do
    Agent.update(agent, fn metrics ->
      Map.merge(metrics, updates, fn _k, v1, v2 ->
        if is_integer(v1) and is_integer(v2) do
          v1 + v2
        else
          if is_list(v1) and is_list(v2) do
            v1 ++ v2
          else
            v2
          end
        end
      end)
    end)
  end

  @doc """
  Gets current metrics from the agent.
  """
  def get(agent) do
    Agent.get(agent, & &1)
  end

  @doc """
  Stops the metrics agent.
  """
  def stop(agent) do
    Agent.stop(agent)
  end

  @doc """
  Logs summary metrics for a sync operation.
  """
  def log_summary(server_name, operation_name, metrics, duration_ms) do
    metrics_str =
      metrics
      |> Map.drop([:start_time, :errors])
      |> Enum.map(fn {k, v} -> "#{k}: #{v}" end)
      |> Enum.join("\n")

    Logger.info("""
    #{operation_name} completed for server #{server_name}
    Duration: #{duration_ms / 1000} seconds
    #{metrics_str}
    Errors: #{length(Map.get(metrics, :errors, []))}
    """)
  end
end
