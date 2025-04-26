defmodule StreamystatServer.Jellyfin.Sync.Items.Core do
  @moduledoc """
  Core functionality for syncing all Jellyfin items from libraries.
  """

  require Logger

  alias StreamystatServer.Repo
  alias StreamystatServer.Jellyfin.Client
  alias StreamystatServer.Jellyfin.Models.Item
  alias StreamystatServer.Jellyfin.Sync.Utils
  alias StreamystatServer.Jellyfin.Sync.Metrics
  alias StreamystatServer.Jellyfin.Sync.Items.Mapper

  # Default batch sizes
  @item_page_size 500
  @db_batch_size 1000

  @doc """
  Synchronizes all media items from a Jellyfin server.
  Processes each library in parallel up to the concurrency limit.
  """
  def sync_items(server, user_options \\ %{}) do
    start_time = System.monotonic_time(:millisecond)

    options = Map.merge(default_options(), user_options)
    metrics = initialize_metrics()
    {:ok, metrics_agent} = Metrics.start_agent(metrics)

    Logger.info("Starting item sync for all libraries")

    result =
      with {:ok, libraries} <- Client.get_libraries(server) do
        process_libraries(server, libraries, metrics_agent, options)
      else
        {:error, reason} ->
          Metrics.update(metrics_agent, %{errors: [reason]})
          Logger.error("Failed to fetch libraries: #{inspect(reason)}")
          {:error, reason}
      end

    end_time = System.monotonic_time(:millisecond)
    duration_ms = end_time - start_time

    final_metrics = Metrics.get(metrics_agent)
    Metrics.stop(metrics_agent)
    Metrics.log_summary(server.name, "Items sync", final_metrics, duration_ms)

    {result, final_metrics}
  end

  # Private functions

  defp default_options do
    %{
      max_library_concurrency: 2,
      db_batch_size: @db_batch_size,
      api_request_delay_ms: 100,
      item_page_size: @item_page_size,
      max_retries: 3,
      retry_initial_delay_ms: 1000,
      adaptive_throttling: true
    }
  end

  defp initialize_metrics do
    %{
      libraries_processed: 0,
      items_processed: 0,
      errors: [],
      api_requests: 0,
      database_operations: 0,
      start_time: DateTime.utc_now()
    }
  end

  defp process_libraries(server, libraries, metrics_agent, options) do
    max_concurrency = options.max_library_concurrency

    results =
      Task.async_stream(
        libraries,
        fn library ->
          Metrics.update(metrics_agent, %{api_requests: 1})
          result = sync_library_items(server, library["Id"], metrics_agent, options)
          Metrics.update(metrics_agent, %{libraries_processed: 1})
          result
        end,
        max_concurrency: max_concurrency,
        timeout: 600_000
      )
      |> Enum.map(fn {:ok, result} -> result end)

    total_count = Enum.sum(Enum.map(results, fn {_, count, _} -> count end))
    total_errors = Enum.flat_map(results, fn {_, _, errors} -> errors end)

    Metrics.update(metrics_agent, %{items_processed: total_count, errors: total_errors})

    case total_errors do
      [] ->
        Logger.info("Synced #{total_count} items across all libraries")
        {:ok, total_count}

      _ ->
        Logger.warning("Synced #{total_count} items with #{length(total_errors)} errors across all libraries")
        Logger.warning("Errors: #{inspect(total_errors)}")
        {:partial, total_count, total_errors}
    end
  end

  defp sync_library_items(server, jellyfin_library_id, metrics_agent, options) do
    Logger.info("Starting item sync for Jellyfin library #{jellyfin_library_id}")

    with {:ok, library} <- Utils.get_library_by_jellyfin_id(jellyfin_library_id, server.id) do
      try do
        batch_size = options.item_page_size
        db_batch_size = options.db_batch_size

        {items_count, errors} =
          fetch_all_library_items(server, jellyfin_library_id, batch_size, metrics_agent)
          |> process_items(library.id, server.id, db_batch_size, metrics_agent)

        finalize_library_sync(library, items_count, errors)
      rescue
        e ->
          log_library_error(e, library, metrics_agent)
          {:error, 0, [inspect(e)]}
      end
    else
      {:error, :library_not_found}  ->
        handle_library_not_found(jellyfin_library_id, server.id, metrics_agent)
        {:error, 0, ["Library not found"]}

      {:error, reason}  ->
        log_sync_error(reason, jellyfin_library_id, metrics_agent)
        {:error, 0, [inspect(reason)]}
    end
  end

  defp fetch_all_library_items(server, library_id, batch_size, metrics_agent) do
    Stream.resource(
      fn -> {0, 0, []} end,
      fn {start_idx, fetched, errs} ->
        Metrics.update(metrics_agent, %{api_requests: 1})

        case Client.get_items_page(server, library_id, start_idx, batch_size) do
          {:ok, {[], _total}} ->
            {:halt, {fetched, errs}}

          {:ok, {items, _total}} ->
            Metrics.update(metrics_agent, %{items_processed: length(items)})
            {[items], {start_idx + batch_size, fetched + length(items), errs}}

          {:error, reason} ->
            Logger.error("Error fetching items: #{inspect(reason)}")
            Metrics.update(metrics_agent, %{errors: [inspect(reason)]})
            {:halt, {fetched, [inspect(reason) | errs]}}
        end
      end,
      fn _ -> :ok end
    )
    |> Stream.flat_map(& &1)
  end

  defp process_items(items_stream, library_id, server_id, db_batch_size, metrics_agent) do
    items_stream
    |> Stream.map(&Mapper.map_jellyfin_item(&1, library_id, server_id))
    |> Stream.chunk_every(db_batch_size)
    |> Stream.map(fn batch ->
      Metrics.update(metrics_agent, %{database_operations: 1})
      save_items_batch(batch, metrics_agent)
    end)
    |> Enum.reduce({0, []}, fn {count, errors}, {total_count, all_errors} ->
      {total_count + count, all_errors ++ errors}
    end)
  end

  defp save_items_batch(batch, metrics_agent) do
    # Deduplicate by {jellyfin_id, library_id}
    deduped_items =
      batch
      |> Enum.reduce(%{}, fn item, acc ->
        key = {item.jellyfin_id, item.library_id}
        Map.update(acc, key, item, fn existing ->
          if item.updated_at > existing.updated_at, do: item, else: existing
        end)
      end)
      |> Map.values()

    try do
      {count, conflict_errors} =
        Repo.insert_all(
          Item,
          deduped_items,
          on_conflict: {:replace_all_except, [:id]},
          conflict_target: [:jellyfin_id, :library_id]
        )

      {count, List.wrap(conflict_errors)}
    rescue
      e ->
        Logger.error("Batch insert failed: #{Exception.message(e)} — falling back to per‑item inserts.")
        insert_items_individually(deduped_items, metrics_agent)
    end
  end

  defp insert_items_individually(items, metrics_agent) do
    Enum.reduce(items, {0, []}, fn attrs, {count, errors} ->
      cs = Item.changeset(%Item{}, attrs)

      case Repo.insert(cs,
             on_conflict: {:replace_all_except, [:id]},
             conflict_target: [:jellyfin_id, :library_id]
           ) do
        {:ok, _} ->
          {count + 1, errors}

        {:error, cs_err} ->
          error_info = {attrs.jellyfin_id, cs_err.errors}
          Logger.error("  • Skipping item #{attrs.jellyfin_id}: #{inspect(cs_err.errors)}")
          Metrics.update(metrics_agent, %{errors: [inspect(error_info)]})
          {count, [error_info | errors]}
      end
    end)
  end

  defp finalize_library_sync(library, items_count, errors) do
    case errors do
      [] ->
        Logger.info("Synced #{items_count} items for library #{library.name}")
        {:ok, items_count, []}

      errors ->
        Logger.warning("Synced #{items_count} items for library #{library.name} with #{length(errors)} errors")
        {:partial, items_count, errors}
    end
  end

  defp log_library_error(error, library, metrics_agent) do
    library_name = if is_map(library), do: library.name, else: "unknown"
    Metrics.update(metrics_agent, %{errors: [inspect(error)]})
    Logger.error("Error syncing items for library #{library_name}: #{inspect(error)}")
  end

  defp handle_library_not_found(jellyfin_library_id, server_id, metrics_agent) do
    Metrics.update(metrics_agent, %{errors: ["Library not found"]})
    Logger.error("Library #{jellyfin_library_id} not found for server #{server_id}")
  end

  defp log_sync_error(reason, jellyfin_library_id, metrics_agent) do
    Metrics.update(metrics_agent, %{errors: [inspect(reason)]})
    Logger.error("Failed to sync items for Jellyfin library #{jellyfin_library_id}: #{inspect(reason)}")
  end
end
