defmodule StreamystatServer.Jellyfin.Sync.Activities do
  @moduledoc """
  Handles synchronization of Jellyfin activities to the local database.
  """

  require Logger

  alias StreamystatServer.Repo
  alias StreamystatServer.Jellyfin.Client
  alias StreamystatServer.Jellyfin.Models.User
  alias StreamystatServer.Activities.Models.Activity
  alias StreamystatServer.Jellyfin.Sync.Utils
  alias StreamystatServer.Jellyfin.Sync.Metrics

  @doc """
  Synchronizes all activities from a Jellyfin server to the local database.
  Uses batch processing to handle large datasets efficiently.
  """
  def sync_activities(server, user_options \\ %{}) do
    start_time = System.monotonic_time(:millisecond)

    options = Map.merge(%{batch_size: 5000}, user_options)

    metrics = %{
      activities_processed: 0,
      activities_inserted: 0,
      api_requests: 0,
      database_operations: 0,
      errors: [],
      start_time: DateTime.utc_now()
    }

    {:ok, metrics_agent} = Metrics.start_agent(metrics)

    Logger.info("Starting full activity sync for server #{server.name}")

    result =
      Stream.resource(
        fn -> {0, 0} end,
        fn {start_index, total_synced} ->
          Metrics.update(metrics_agent, %{api_requests: 1})

          case Client.get_activities(server, start_index, options.batch_size) do
            {:ok, []} ->
              {:halt, {start_index, total_synced}}

            {:ok, activities} ->
              batch_size = length(activities)
              Metrics.update(metrics_agent, %{activities_processed: batch_size})

              {[{activities, start_index}],
               {start_index + options.batch_size, total_synced + batch_size}}

            {:error, reason} ->
              Logger.error("Failed to fetch activities: #{inspect(reason)}")
              Metrics.update(metrics_agent, %{errors: [reason]})
              {:halt, {start_index, total_synced}}
          end
        end,
        fn _ -> :ok end
      )
      |> Stream.map(fn {activities, _index} ->
        new_activities = Enum.map(activities, &map_activity(&1, server))

        Metrics.update(metrics_agent, %{database_operations: 1})

        try do
          {inserted, _} = Repo.insert_all(Activity, new_activities, on_conflict: :nothing)
          Metrics.update(metrics_agent, %{activities_inserted: inserted})
          {:ok, inserted}
        rescue
          e ->
            Logger.error("Failed to insert activities: #{inspect(e)}")
            Metrics.update(metrics_agent, %{errors: [inspect(e)]})
            {:error, inspect(e)}
        end
      end)
      |> Enum.reduce(
        {:ok, 0, []},
        fn
          {:ok, count}, {:ok, total, errors} ->
            {:ok, total + count, errors}

          {:error, error}, {_, total, errors} ->
            {:error, total, [error | errors]}
        end
      )

    end_time = System.monotonic_time(:millisecond)
    duration_ms = end_time - start_time

    final_metrics = Metrics.get(metrics_agent)
    Metrics.stop(metrics_agent)

    Metrics.log_summary(
      server.name,
      "Activity sync",
      final_metrics,
      duration_ms
    )

    case result do
      {:ok, count, []} ->
        Logger.info("Successfully synced #{count} activities for server #{server.name}")
        {{:ok, count}, final_metrics}

      {:ok, count, errors} ->
        Logger.warning("Synced #{count} activities with #{length(errors)} errors")
        {{:partial, count, errors}, final_metrics}

      {:error, _, errors} ->
        Logger.error("Failed to sync activities for server #{server.name}")
        {{:error, errors}, final_metrics}
    end
  end

  @doc """
  Synchronizes recent activities (last 25) from a Jellyfin server.
  """
  def sync_recent(server) do
    start_time = System.monotonic_time(:millisecond)

    metrics = %{
      activities_processed: 0,
      activities_inserted: 0,
      api_requests: 1,
      database_operations: 0,
      errors: []
    }

    Logger.info("Starting recent activity sync for server #{server.name}")

    {result, updated_metrics} =
      case Client.get_activities(server, 0, 25) do
        {:ok, activities} ->
          metrics = Map.put(metrics, :activities_processed, length(activities))
          new_activities = Enum.map(activities, &map_activity(&1, server))
          metrics = Map.put(metrics, :database_operations, 1)

          try do
            {inserted, _} = Repo.insert_all(Activity, new_activities, on_conflict: :nothing)

            metrics = Map.put(metrics, :activities_inserted, inserted)
            {{:ok, inserted}, metrics}
          rescue
            e ->
              Logger.error("Error inserting activities: #{inspect(e)}")

              metrics =
                Map.update(metrics, :errors, [inspect(e)], fn errors -> [inspect(e) | errors] end)

              {{:error, inspect(e)}, metrics}
          end

        {:error, reason} ->
          metrics = Map.update(metrics, :errors, [reason], fn errors -> [reason | errors] end)
          {{:error, reason}, metrics}
      end

    end_time = System.monotonic_time(:millisecond)
    duration_ms = end_time - start_time

    Metrics.log_summary(
      server.name,
      "Recent activity sync",
      updated_metrics,
      duration_ms
    )

    {result, updated_metrics}
  end

  @doc """
  Maps a Jellyfin activity JSON object to a map suitable for database insertion.
  """
  def map_activity(activity, server) do
    user_info = get_user_info(server, activity["UserId"])

    %{
      jellyfin_id: activity["Id"],
      name: activity["Name"],
      short_overview: activity["ShortOverview"],
      type: activity["Type"],
      date: Utils.parse_datetime_to_utc(activity["Date"]),
      user_jellyfin_id: user_info[:jellyfin_id],
      server_id: server.id,
      severity: activity["Severity"],
      inserted_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second),
      updated_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
    }
  end

  @doc """
  Resolves a Jellyfin user ID to a map with jellyfin_id.
  Returns %{jellyfin_id: nil} if not found or for special system user IDs.
  """
  def get_user_info(server, jellyfin_user_id) do
    case jellyfin_user_id do
      "00000000000000000000000000000000" ->
        %{jellyfin_id: nil}

      nil ->
        %{jellyfin_id: nil}

      id ->
        case Repo.get_by(User, jellyfin_id: id, server_id: server.id) do
          nil -> %{jellyfin_id: nil}
          user -> %{jellyfin_id: user.jellyfin_id}
        end
    end
  end
end
