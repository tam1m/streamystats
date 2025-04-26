defmodule StreamystatServer.Jellyfin.Sync do
  import Ecto.Query
  alias StreamystatServer.Repo
  alias StreamystatServer.Jellyfin.Client
  alias StreamystatServer.Jellyfin.Models.Library
  alias StreamystatServer.Jellyfin.Models.Item
  alias StreamystatServer.Jellyfin.Models.User
  alias StreamystatServer.Activities.Models.Activity

  require Logger

  @item_page_size 500
  @db_batch_size 1000

  @sync_options %{
    max_library_concurrency: 2,
    db_batch_size: 1000,
    api_request_delay_ms: 100,
    item_page_size: 500,
    max_retries: 3,
    retry_initial_delay_ms: 1000,
    adaptive_throttling: true
  }

  def sync_users(server) do
    Logger.info("Starting user sync for server #{server.name}")

    case Client.get_users(server) do
      {:ok, jellyfin_users} ->
        users_data = Enum.map(jellyfin_users, &map_jellyfin_user(&1, server.id))

        # Extract jellyfin_ids from the API response to identify active users
        jellyfin_ids = Enum.map(jellyfin_users, fn user -> user["Id"] end)

        Repo.transaction(fn ->
          # Insert or update existing users
          {updated_count, _} =
            Repo.insert_all(
              StreamystatServer.Jellyfin.Models.User,
              users_data,
              on_conflict: {:replace, [:name]},
              conflict_target: [:jellyfin_id, :server_id]
            )

          # Delete users that no longer exist in Jellyfin
          {deleted_count, _} =
            from(u in User,
              where: u.server_id == ^server.id and u.jellyfin_id not in ^jellyfin_ids
            )
            |> Repo.delete_all()

          {updated_count, deleted_count}
        end)
        |> case do
          {:ok, {updated_count, deleted_count}} ->
            Logger.info(
              "Successfully synced users for server #{server.name} - Updated: #{updated_count}, Deleted: #{deleted_count}"
            )

            {:ok, %{updated: updated_count, deleted: deleted_count}}

          {:error, reason} ->
            Logger.error("Failed to sync users for server #{server.name}: #{inspect(reason)}")
            {:error, reason}
        end

      {:error, reason} ->
        Logger.error("Failed to sync users for server #{server.name}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def sync_libraries(server) do
    Logger.info("Starting library sync for server #{server.name}")

    case Client.get_libraries(server) do
      {:ok, jellyfin_libraries} ->
        libraries = Enum.map(jellyfin_libraries, &map_jellyfin_library(&1, server.id))

        result =
          Enum.reduce(libraries, {0, []}, fn library, {count, errors} ->
            case Repo.insert(Library.changeset(%Library{}, library),
                   on_conflict: {:replace_all_except, [:id]},
                   conflict_target: [:jellyfin_id, :server_id]
                 ) do
              {:ok, _} ->
                {count + 1, errors}

              {:error, changeset} ->
                Logger.warning("Error inserting library: #{inspect(changeset.errors)}")
                {count, [changeset.errors | errors]}
            end
          end)

        case result do
          {count, []} ->
            Logger.info("Synced #{count} libraries")
            {:ok, count}

          {count, errors} ->
            Logger.warning("Synced #{count} libraries with #{length(errors)} errors")
            Logger.warning("Errors: #{inspect(errors)}")
            {:partial, count, errors}
        end

      {:error, reason} ->
        Logger.error("Failed to sync libraries: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def sync_items(server, user_options \\ %{}) do
    start_time = System.monotonic_time(:millisecond)

    options = Map.merge(@sync_options, user_options)

    metrics = %{
      libraries_processed: 0,
      items_processed: 0,
      errors: [],
      api_requests: 0,
      database_operations: 0,
      start_time: DateTime.utc_now()
    }

    {:ok, metrics_agent} = Agent.start_link(fn -> metrics end)

    Logger.info("Starting item sync for all libraries")

    result =
      case Client.get_libraries(server) do
        {:ok, libraries} ->
          max_concurrency = options.max_library_concurrency

          results =
            Task.async_stream(
              libraries,
              fn library ->
                update_metrics(metrics_agent, %{api_requests: 1})

                result = sync_library_items(server, library["Id"], metrics_agent, options)

                update_metrics(metrics_agent, %{libraries_processed: 1})

                result
              end,
              max_concurrency: max_concurrency,
              timeout: 600_000
            )
            |> Enum.map(fn {:ok, result} -> result end)

          total_count = Enum.sum(Enum.map(results, fn {_, count, _} -> count end))
          total_errors = Enum.flat_map(results, fn {_, _, errors} -> errors end)

          update_metrics(metrics_agent, %{items_processed: total_count, errors: total_errors})

          case total_errors do
            [] ->
              Logger.info("Synced #{total_count} items across all libraries")
              {:ok, total_count}

            _ ->
              Logger.warning(
                "Synced #{total_count} items with #{length(total_errors)} errors across all libraries"
              )

              Logger.warning("Errors: #{inspect(total_errors)}")
              {:partial, total_count, total_errors}
          end

        {:error, reason} ->
          update_metrics(metrics_agent, %{errors: [reason]})
          Logger.error("Failed to fetch libraries: #{inspect(reason)}")
          {:error, reason}
      end

    end_time = System.monotonic_time(:millisecond)
    duration_ms = end_time - start_time

    final_metrics = Agent.get(metrics_agent, & &1)
    Agent.stop(metrics_agent)

    Logger.info("""
    Sync completed for server #{server.name}
    Duration: #{duration_ms / 1000} seconds
    Libraries processed: #{final_metrics.libraries_processed}
    Items processed: #{final_metrics.items_processed}
    API requests: #{final_metrics.api_requests}
    Database operations: #{final_metrics.database_operations}
    Errors: #{length(final_metrics.errors)}
    """)

    {result, final_metrics}
  end

  def sync_activities(server, user_options \\ %{}) do
    start_time = System.monotonic_time(:millisecond)

    options = Map.merge(@sync_options, %{batch_size: 5000})
    options = Map.merge(options, user_options)

    metrics = %{
      activities_processed: 0,
      activities_inserted: 0,
      api_requests: 0,
      database_operations: 0,
      errors: [],
      start_time: DateTime.utc_now()
    }

    {:ok, metrics_agent} = Agent.start_link(fn -> metrics end)

    Logger.info("Starting full activity sync for server #{server.name}")

    result =
      Stream.resource(
        fn -> {0, 0} end,
        fn {start_index, total_synced} ->
          update_metrics(metrics_agent, %{api_requests: 1})

          case Client.get_activities(server, start_index, options.batch_size) do
            {:ok, []} ->
              {:halt, {start_index, total_synced}}

            {:ok, activities} ->
              batch_size = length(activities)
              update_metrics(metrics_agent, %{activities_processed: batch_size})

              {[{activities, start_index}],
               {start_index + options.batch_size, total_synced + batch_size}}

            {:error, reason} ->
              Logger.error("Failed to fetch activities: #{inspect(reason)}")
              update_metrics(metrics_agent, %{errors: [reason]})
              {:halt, {start_index, total_synced}}
          end
        end,
        fn _ -> :ok end
      )
      |> Stream.map(fn {activities, _index} ->
        new_activities = Enum.map(activities, &map_activity(&1, server))

        update_metrics(metrics_agent, %{database_operations: 1})

        try do
          {inserted, _} = Repo.insert_all(Activity, new_activities, on_conflict: :nothing)
          update_metrics(metrics_agent, %{activities_inserted: inserted})
          {:ok, inserted}
        rescue
          e ->
            Logger.error("Failed to insert activities: #{inspect(e)}")
            update_metrics(metrics_agent, %{errors: [inspect(e)]})
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

    final_metrics = Agent.get(metrics_agent, & &1)
    Agent.stop(metrics_agent)

    Logger.info("""
    Activity sync completed for server #{server.name}
    Duration: #{duration_ms / 1000} seconds
    Activities processed: #{final_metrics.activities_processed}
    Activities inserted: #{final_metrics.activities_inserted}
    API requests: #{final_metrics.api_requests}
    Database operations: #{final_metrics.database_operations}
    Errors: #{length(final_metrics.errors)}
    """)

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

  def sync_recent_activities(server) do
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

    Logger.info("""
    Recent activity sync completed for server #{server.name}
    Duration: #{duration_ms / 1000} seconds
    Activities processed: #{updated_metrics.activities_processed}
    Activities inserted: #{updated_metrics.activities_inserted}
    API requests: #{updated_metrics.api_requests}
    Database operations: #{updated_metrics.database_operations}
    Errors: #{length(updated_metrics.errors)}
    """)

    Logger.info("Finished recent activity sync for server #{server.name}")
    {result, updated_metrics}
  end

  @doc """
  Syncs recently added items from Jellyfin.
  Fetches the latest 20 items and adds them to the database if they don't exist.
  Only updates existing items if specific tracked fields have changed.
  """
  def sync_recently_added_items(server, limit \\ 20) do
    start_time = System.monotonic_time(:millisecond)

    metrics = %{
      items_processed: 0,
      items_inserted: 0,
      items_updated: 0,
      items_unchanged: 0,
      api_requests: 1,
      database_operations: 0,
      errors: []
    }

    Logger.info("Starting recently added items sync for server #{server.name}")

    {result, updated_metrics} =
      try do
        case Client.get_recently_added_items(server, limit) do
          {:ok, items} ->
            metrics = Map.put(metrics, :items_processed, length(items))
            Logger.debug("Retrieved #{length(items)} recently added items from Jellyfin")

            # Fetch libraries and build a lookup map
            libraries = get_libraries_by_server(server.id)

            library_map =
              Enum.reduce(libraries, %{}, fn lib, acc ->
                Map.put(acc, lib.jellyfin_id, lib.id)
              end)

            # Process and map items with detailed error logging
            {valid_items, invalid_items} =
              Enum.reduce(items, {[], []}, fn item, {valid, invalid} ->
                try do
                  library_id = get_library_id_for_item(item, library_map, server)

                  case library_id do
                    nil ->
                      Logger.warning(
                        "Could not determine library for item #{item["Id"]} of type #{item["Type"]}"
                      )

                      {valid, [%{id: item["Id"], error: "Library not found"} | invalid]}

                    found_library_id ->
                      # Map the item with the correct library ID
                      mapped_item = map_jellyfin_item(item, found_library_id, server.id)
                      {[mapped_item | valid], invalid}
                  end
                rescue
                  e ->
                    # Catch any mapping errors
                    Logger.error(
                      "Error mapping item #{inspect(item["Id"])}: #{Exception.message(e)}"
                    )

                    {valid, [%{id: item["Id"], error: Exception.message(e)} | invalid]}
                end
              end)

            Logger.debug(
              "Successfully mapped #{length(valid_items)} items, skipped #{length(invalid_items)} items"
            )

            case valid_items do
              [] ->
                Logger.info("No valid items to insert")
                {{:ok, 0, 0, 0}, metrics}

              _ ->
                metrics = Map.put(metrics, :database_operations, 1)

                # Fetch existing items with all fields to compare
                jellyfin_ids = Enum.map(valid_items, & &1.jellyfin_id)

                existing_items =
                  Repo.all(
                    from(i in Item,
                      where: i.jellyfin_id in ^jellyfin_ids and i.server_id == ^server.id
                    )
                  )

                existing_map =
                  Enum.into(existing_items, %{}, fn item -> {item.jellyfin_id, item} end)

                # Fields that we track for changes
                tracked_fields = [
                  :name,
                  :original_title,
                  :etag,
                  :container,
                  :sort_name,
                  :premiere_date,
                  :external_urls,
                  :path,
                  :official_rating,
                  :overview,
                  :genres,
                  :community_rating,
                  :runtime_ticks,
                  :production_year,
                  :is_folder,
                  :parent_id,
                  :media_type,
                  :width,
                  :height,
                  :series_name,
                  :series_id,
                  :season_id,
                  :season_name,
                  :index_number,
                  :parent_index_number,
                  :primary_image_tag,
                  :backdrop_image_tags,
                  :image_blur_hashes,
                  :video_type,
                  :has_subtitles,
                  :channel_id,
                  :parent_backdrop_item_id,
                  :parent_backdrop_image_tags,
                  :parent_thumb_item_id,
                  :parent_thumb_image_tag,
                  :location_type,
                  :primary_image_aspect_ratio,
                  :series_primary_image_tag,
                  :primary_image_thumb_tag,
                  :primary_image_logo_tag
                ]

                # Separate items into inserts and updates
                {items_to_insert, items_to_update, unchanged_items} =
                  Enum.reduce(valid_items, {[], [], []}, fn item, {inserts, updates, unchanged} ->
                    case Map.get(existing_map, item.jellyfin_id) do
                      nil ->
                        # New item, add to inserts
                        {[item | inserts], updates, unchanged}

                      existing ->
                        # Check if any tracked field has changed
                        if fields_changed?(existing, item, tracked_fields) do
                          {inserts, [item | updates], unchanged}
                        else
                          {inserts, updates, [item | unchanged]}
                        end
                    end
                  end)

                # Insert new items
                insert_result =
                  unless Enum.empty?(items_to_insert) do
                    {count, _} = Repo.insert_all(Item, items_to_insert)
                    count
                  else
                    0
                  end

                # Update changed items
                update_result =
                  Enum.reduce(items_to_update, 0, fn item, count ->
                    # Convert struct/map to keyword list for update_all
                    update_fields =
                      tracked_fields
                      |> Enum.map(fn field -> {field, Map.get(item, field)} end)
                      |> Enum.into([])

                    {updated, _} =
                      Repo.update_all(
                        from(i in Item,
                          where:
                            i.jellyfin_id == ^item.jellyfin_id and
                              i.server_id == ^server.id
                        ),
                        set: update_fields
                      )

                    count + updated
                  end)

                unchanged_count = length(unchanged_items)

                metrics =
                  metrics
                  |> Map.put(:items_inserted, insert_result)
                  |> Map.put(:items_updated, update_result)
                  |> Map.put(:items_unchanged, unchanged_count)

                if length(invalid_items) > 0 do
                  metrics =
                    Map.update(
                      metrics,
                      :errors,
                      invalid_items,
                      fn errors -> errors ++ invalid_items end
                    )

                  {{:partial, insert_result, update_result, unchanged_count, invalid_items},
                   metrics}
                else
                  {{:ok, insert_result, update_result, unchanged_count}, metrics}
                end
            end

          {:error, reason} ->
            Logger.error("API error when fetching recently added items: #{inspect(reason)}")
            metrics = Map.update(metrics, :errors, [reason], fn errors -> [reason | errors] end)
            {{:error, reason}, metrics}
        end
      rescue
        e ->
          stacktrace = Exception.format_stacktrace()

          error_message =
            "Unexpected error in sync_recently_added_items: #{Exception.message(e)}\n#{stacktrace}"

          Logger.error(error_message)

          {
            {:error, Exception.message(e)},
            Map.update(metrics, :errors, [error_message], fn errors ->
              [error_message | errors]
            end)
          }
      end

    end_time = System.monotonic_time(:millisecond)
    duration_ms = end_time - start_time

    Logger.info("""
    Recently added items sync completed for server #{server.name}
    Duration: #{duration_ms / 1000} seconds
    Items processed: #{updated_metrics.items_processed}
    Items inserted (new): #{updated_metrics.items_inserted}
    Items updated (changed): #{updated_metrics.items_updated}
    Items unchanged: #{updated_metrics.items_unchanged}
    API requests: #{updated_metrics.api_requests}
    Database operations: #{updated_metrics.database_operations}
    Errors: #{length(updated_metrics.errors)}
    """)

    {result, updated_metrics}
  end

  # Helper function to determine if fields have changed
  defp fields_changed?(existing_item, new_item, fields) do
    Enum.any?(fields, fn field ->
      Map.get(existing_item, field) != Map.get(new_item, field)
    end)
  end

  defp get_library_id_for_item(item, library_map, server) do
    Logger.debug("Determining library for item #{item["Id"]} (#{item["Name"]}) type=#{item["Type"]}")

    # First check if we already have the library directly from parent ID
    parent_id = item["ParentId"]

    if parent_id && Map.has_key?(library_map, parent_id) do
      # If the parent is a library, use it directly
      library_id = Map.get(library_map, parent_id)
      Logger.debug("Found library directly from parent_id=#{parent_id} -> library_id=#{library_id}")
      library_id
    else
      # Log why we couldn't use the parent_id approach
      cond do
        parent_id == nil ->
          Logger.debug("Item #{item["Id"]} has no parent_id, will try API method")
        !Map.has_key?(library_map, parent_id) ->
          Logger.debug("Parent #{parent_id} not found in library map, will try API method")
        true ->
          Logger.debug("Fallback to API method for unknown reason")
      end

      # Otherwise use our recursive API-based approach
      Logger.debug("Making API call to determine library for item #{item["Id"]}")

      case Client.get_library_id(server, item["Id"]) do
        {:ok, library_jellyfin_id} ->
          # Convert the Jellyfin library ID to our internal DB ID
          library_id = Map.get(library_map, library_jellyfin_id)

          if library_id do
            Logger.debug("API returned library_jellyfin_id=#{library_jellyfin_id} -> library_id=#{library_id}")
            library_id
          else
            Logger.warning("API returned library_jellyfin_id=#{library_jellyfin_id}, but no matching DB library found")
            nil
          end

        {:error, reason} ->
          Logger.warning("Could not determine library for item #{item["Id"]} (#{item["Name"]}): #{inspect(reason)}")
          Logger.debug("Item details: type=#{item["Type"]}, parent_id=#{parent_id}")
          nil
      end
    end
  end

  # Helper function to get all libraries for a server
  defp get_libraries_by_server(server_id) do
    Repo.all(from(l in Library, where: l.server_id == ^server_id))
  end

  defp sanitize_string(nil), do: nil

  defp sanitize_string(str) when is_binary(str) do
    str
    |> String.replace(<<0>>, "")
    |> String.replace(~r/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/, "")
  end

  defp sanitize_string(other), do: other

  defp sync_library_items(server, jellyfin_library_id, metrics_agent, options) do
    Logger.info("Starting item sync for Jellyfin library #{jellyfin_library_id}")

    with {:ok, library} <- get_library_by_jellyfin_id(jellyfin_library_id, server.id) do
      try do
        batch_size = options.item_page_size || @item_page_size
        db_batch_sz = options.db_batch_size || @db_batch_size

        {total_count, errors} =
          Stream.resource(
            fn -> {0, 0, []} end,
            fn {start_idx, fetched, errs} ->
              if metrics_agent, do: update_metrics(metrics_agent, %{api_requests: 1})

              case Client.get_items_page(server, jellyfin_library_id, start_idx, batch_size) do
                {:ok, {[], _total}} ->
                  {:halt, {fetched, errs}}

                {:ok, {items, _total}} ->
                  if metrics_agent,
                    do: update_metrics(metrics_agent, %{items_processed: length(items)})

                  {[items], {start_idx + batch_size, fetched + length(items), errs}}

                {:error, reason} ->
                  Logger.error("Error fetching items: #{inspect(reason)}")

                  if metrics_agent,
                    do: update_metrics(metrics_agent, %{errors: [inspect(reason)]})

                  {:halt, {fetched, [inspect(reason) | errs]}}
              end
            end,
            fn _ -> :ok end
          )
          |> Stream.flat_map(& &1)
          |> Stream.map(&map_jellyfin_item(&1, library.id, server.id))
          |> Stream.chunk_every(db_batch_sz)
          |> Stream.map(fn batch ->
            if metrics_agent, do: update_metrics(metrics_agent, %{database_operations: 1})

            # dedupe by {jellyfin_id, library_id}
            deduped =
              batch
              |> Enum.reduce(%{}, fn item, acc ->
                key = {item.jellyfin_id, item.library_id}

                Map.update(acc, key, item, fn existing ->
                  if item.updated_at > existing.updated_at, do: item, else: existing
                end)
              end)
              |> Map.values()

            # try fast batch insert
            try do
              {count, conflict_errors} =
                Repo.insert_all(
                  Item,
                  deduped,
                  on_conflict: {:replace_all_except, [:id]},
                  conflict_target: [:jellyfin_id, :library_id]
                )

              {count, List.wrap(conflict_errors)}
            rescue
              e ->
                Logger.error(
                  "Batch insert failed: #{Exception.message(e)} — falling back to per‑item inserts."
                )

                # slow path: insert one by one
                Enum.reduce(deduped, {0, []}, fn attrs, {c, errs_acc} ->
                  cs = Item.changeset(%Item{}, attrs)

                  case Repo.insert(cs,
                         on_conflict: {:replace_all_except, [:id]},
                         conflict_target: [:jellyfin_id, :library_id]
                       ) do
                    {:ok, _} ->
                      {c + 1, errs_acc}

                    {:error, cs_err} ->
                      error_info = {attrs.jellyfin_id, cs_err.errors}

                      Logger.error(
                        "  • Skipping item #{attrs.jellyfin_id}: #{inspect(cs_err.errors)}"
                      )

                      if metrics_agent,
                        do: update_metrics(metrics_agent, %{errors: [inspect(error_info)]})

                      {c, [error_info | errs_acc]}
                  end
                end)
            end
          end)
          |> Enum.reduce({0, []}, fn {cnt, es}, {sum, all_es} ->
            {sum + cnt, all_es ++ es}
          end)

        case errors do
          [] ->
            Logger.info("Synced #{total_count} items for library #{library.name}")
            {:ok, total_count, []}

          errs ->
            Logger.warning(
              "Synced #{total_count} items for library #{library.name} with #{length(errs)} errors"
            )

            {:partial, total_count, errs}
        end
      rescue
        e ->
          if metrics_agent, do: update_metrics(metrics_agent, %{errors: [inspect(e)]})
          Logger.error("Error syncing items for library #{library.name}: #{inspect(e)}")
          {:error, 0, [inspect(e)]}
      end
    else
      {:error, :library_not_found} ->
        if metrics_agent, do: update_metrics(metrics_agent, %{errors: ["Library not found"]})
        Logger.error("Library #{jellyfin_library_id} not found for server #{server.id}")
        {:error, 0, ["Library not found"]}

      {:error, reason} ->
        if metrics_agent, do: update_metrics(metrics_agent, %{errors: [inspect(reason)]})

        Logger.error(
          "Failed to sync items for Jellyfin library #{jellyfin_library_id}: #{inspect(reason)}"
        )

        {:error, 0, [inspect(reason)]}
    end
  end

  defp update_metrics(nil, _updates), do: :ok

  defp update_metrics(agent, updates) do
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

  defp map_activity(activity, server) do
    %{
      jellyfin_id: activity["Id"],
      name: activity["Name"],
      short_overview: activity["ShortOverview"],
      type: activity["Type"],
      date: parse_datetime_to_utc(activity["Date"]),
      user_id: get_user_id(server, activity["UserId"]),
      server_id: server.id,
      severity: activity["Severity"],
      inserted_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second),
      updated_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
    }
  end

  defp get_user_id(server, jellyfin_user_id) do
    case jellyfin_user_id do
      "00000000000000000000000000000000" ->
        nil

      nil ->
        nil

      id ->
        case Repo.get_by(User, jellyfin_id: id, server_id: server.id) do
          nil -> nil
          user -> user.id
        end
    end
  end

  defp parse_datetime_to_utc(nil), do: nil
  defp parse_datetime_to_utc(""), do: nil

  defp parse_datetime_to_utc(datetime_string) when is_binary(datetime_string) do
    case DateTime.from_iso8601(datetime_string) do
      {:ok, datetime, _offset} ->
        DateTime.truncate(datetime, :second)

      {:error, _} ->
        case NaiveDateTime.from_iso8601(datetime_string) do
          {:ok, naive_datetime} ->
            naive_datetime
            |> DateTime.from_naive!("Etc/UTC")
            |> DateTime.truncate(:second)

          {:error, _} ->
            Logger.warning("Failed to parse datetime: #{datetime_string}")
            nil
        end
    end
  end

  defp parse_datetime_to_utc(_), do: nil

  defp get_library_by_jellyfin_id(jellyfin_library_id, server_id) do
    case Repo.get_by(Library, jellyfin_id: jellyfin_library_id, server_id: server_id) do
      nil -> {:error, :library_not_found}
      library -> {:ok, library}
    end
  end

  defp map_jellyfin_item(jellyfin_item, library_id, server_id) do
    # Get primary image tag if it exists
    primary_image_tag =
      case jellyfin_item["ImageTags"] do
        nil -> nil
        tags when is_map(tags) -> Map.get(tags, "Primary")
        _ -> nil
      end

    primary_image_thumb_tag =
      case jellyfin_item["ImageTags"] do
        nil -> nil
        tags when is_map(tags) -> Map.get(tags, "Thumb")
        _ -> nil
      end

    primary_image_logo_tag =
      case jellyfin_item["ImageTags"] do
        nil -> nil
        tags when is_map(tags) -> Map.get(tags, "Logo")
        _ -> nil
      end

    backdrop_image_tags = jellyfin_item["BackdropImageTags"]

    name =
      case sanitize_string(jellyfin_item["Name"]) do
        nil ->
          # Try to use a sensible fallback based on other item properties
          cond do
            is_binary(jellyfin_item["OriginalTitle"]) and jellyfin_item["OriginalTitle"] != "" ->
              sanitize_string(jellyfin_item["OriginalTitle"])

            is_binary(jellyfin_item["SeriesName"]) and jellyfin_item["SeriesName"] != "" ->
              "#{sanitize_string(jellyfin_item["SeriesName"])} - Unknown Episode"

            is_binary(jellyfin_item["Type"]) ->
              "Untitled #{jellyfin_item["Type"]}"

            true ->
              "Untitled Item"
          end

        "" ->
          # Same fallback logic for empty strings
          cond do
            is_binary(jellyfin_item["OriginalTitle"]) and jellyfin_item["OriginalTitle"] != "" ->
              sanitize_string(jellyfin_item["OriginalTitle"])

            is_binary(jellyfin_item["SeriesName"]) and jellyfin_item["SeriesName"] != "" ->
              "#{sanitize_string(jellyfin_item["SeriesName"])} - Unknown Episode"

            is_binary(jellyfin_item["Type"]) ->
              "Untitled #{jellyfin_item["Type"]}"

            true ->
              "Untitled Item"
          end

        valid_name ->
          valid_name
      end

    %{
      jellyfin_id: jellyfin_item["Id"],
      name: name,
      type: sanitize_string(jellyfin_item["Type"]),
      original_title: sanitize_string(jellyfin_item["OriginalTitle"]),
      etag: sanitize_string(jellyfin_item["Etag"]),
      date_created: parse_datetime_to_utc(jellyfin_item["DateCreated"]),
      container: sanitize_string(jellyfin_item["Container"]),
      sort_name: sanitize_string(jellyfin_item["SortName"]),
      premiere_date: parse_datetime_to_utc(jellyfin_item["PremiereDate"]),
      external_urls: jellyfin_item["ExternalUrls"],
      path: sanitize_string(jellyfin_item["Path"]),
      official_rating: sanitize_string(jellyfin_item["OfficialRating"]),
      overview: sanitize_string(jellyfin_item["Overview"]),
      genres: jellyfin_item["Genres"],
      community_rating: parse_float(jellyfin_item["CommunityRating"]),
      runtime_ticks: jellyfin_item["RunTimeTicks"],
      production_year: jellyfin_item["ProductionYear"],
      is_folder: jellyfin_item["IsFolder"],
      parent_id: jellyfin_item["ParentId"],
      media_type: sanitize_string(jellyfin_item["MediaType"]),
      width: jellyfin_item["Width"],
      height: jellyfin_item["Height"],
      library_id: library_id,
      server_id: server_id,
      series_name: sanitize_string(jellyfin_item["SeriesName"]),
      series_id: jellyfin_item["SeriesId"],
      season_id: jellyfin_item["SeasonId"],
      season_name: sanitize_string(jellyfin_item["SeasonName"]),
      index_number: jellyfin_item["IndexNumber"],
      parent_index_number: jellyfin_item["ParentIndexNumber"],
      primary_image_tag: sanitize_string(primary_image_tag),
      primary_image_thumb_tag: sanitize_string(primary_image_thumb_tag),
      primary_image_logo_tag: sanitize_string(primary_image_logo_tag),
      backdrop_image_tags: backdrop_image_tags,
      image_blur_hashes: jellyfin_item["ImageBlurHashes"],
      video_type: sanitize_string(jellyfin_item["VideoType"]),
      has_subtitles: jellyfin_item["HasSubtitles"],
      channel_id: jellyfin_item["ChannelId"],
      parent_backdrop_item_id: jellyfin_item["ParentBackdropItemId"],
      parent_backdrop_image_tags: jellyfin_item["ParentBackdropImageTags"],
      parent_thumb_item_id: jellyfin_item["ParentThumbItemId"],
      parent_thumb_image_tag: jellyfin_item["ParentThumbImageTag"],
      location_type: sanitize_string(jellyfin_item["LocationType"]),
      primary_image_aspect_ratio: parse_float(jellyfin_item["PrimaryImageAspectRatio"]),
      series_primary_image_tag: sanitize_string(jellyfin_item["SeriesPrimaryImageTag"]),
      inserted_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second),
      updated_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
    }
  end

  defp parse_float(nil), do: nil

  defp parse_float(string) when is_binary(string) do
    case Float.parse(string) do
      {float, _} -> float
      :error -> nil
    end
  end

  defp parse_float(number) when is_integer(number), do: number / 1
  defp parse_float(number) when is_float(number), do: number
  defp parse_float(_), do: nil

  defp map_jellyfin_user(user_data, server_id) do
    %{
      jellyfin_id: user_data["Id"],
      name: user_data["Name"],
      server_id: server_id,
      has_password: user_data["HasPassword"],
      has_configured_password: user_data["HasConfiguredPassword"],
      has_configured_easy_password: user_data["HasConfiguredEasyPassword"],
      enable_auto_login: user_data["EnableAutoLogin"],
      last_login_date: parse_datetime_to_utc(user_data["LastLoginDate"]),
      last_activity_date: parse_datetime_to_utc(user_data["LastActivityDate"]),
      is_administrator: user_data["Policy"]["IsAdministrator"],
      is_hidden: user_data["Policy"]["IsHidden"],
      is_disabled: user_data["Policy"]["IsDisabled"],
      enable_user_preference_access: user_data["Policy"]["EnableUserPreferenceAccess"],
      enable_remote_control_of_other_users:
        user_data["Policy"]["EnableRemoteControlOfOtherUsers"],
      enable_shared_device_control: user_data["Policy"]["EnableSharedDeviceControl"],
      enable_remote_access: user_data["Policy"]["EnableRemoteAccess"],
      enable_live_tv_management: user_data["Policy"]["EnableLiveTvManagement"],
      enable_live_tv_access: user_data["Policy"]["EnableLiveTvAccess"],
      enable_media_playback: user_data["Policy"]["EnableMediaPlayback"],
      enable_audio_playback_transcoding: user_data["Policy"]["EnableAudioPlaybackTranscoding"],
      enable_video_playback_transcoding: user_data["Policy"]["EnableVideoPlaybackTranscoding"],
      enable_playback_remuxing: user_data["Policy"]["EnablePlaybackRemuxing"],
      enable_content_deletion: user_data["Policy"]["EnableContentDeletion"],
      enable_content_downloading: user_data["Policy"]["EnableContentDownloading"],
      enable_sync_transcoding: user_data["Policy"]["EnableSyncTranscoding"],
      enable_media_conversion: user_data["Policy"]["EnableMediaConversion"],
      enable_all_devices: user_data["Policy"]["EnableAllDevices"],
      enable_all_channels: user_data["Policy"]["EnableAllChannels"],
      enable_all_folders: user_data["Policy"]["EnableAllFolders"],
      enable_public_sharing: user_data["Policy"]["EnablePublicSharing"],
      invalid_login_attempt_count: user_data["Policy"]["InvalidLoginAttemptCount"],
      login_attempts_before_lockout: user_data["Policy"]["LoginAttemptsBeforeLockout"],
      max_active_sessions: user_data["Policy"]["MaxActiveSessions"],
      remote_client_bitrate_limit: user_data["Policy"]["RemoteClientBitrateLimit"],
      authentication_provider_id: user_data["Policy"]["AuthenticationProviderId"],
      password_reset_provider_id: user_data["Policy"]["PasswordResetProviderId"],
      sync_play_access: user_data["Policy"]["SyncPlayAccess"],
      inserted_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second),
      updated_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
    }
  end

  defp map_jellyfin_library(jellyfin_library, server_id) do
    type = jellyfin_library["CollectionType"] || "unknown"

    sanitized_type =
      case sanitize_string(type) do
        nil -> "unknown"
        sanitized -> sanitized
      end

    %{
      jellyfin_id: jellyfin_library["Id"],
      name: sanitize_string(jellyfin_library["Name"]),
      type: sanitized_type,
      server_id: server_id,
      inserted_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second),
      updated_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
    }
  end
end
