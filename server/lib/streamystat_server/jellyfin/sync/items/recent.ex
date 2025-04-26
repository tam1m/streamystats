defmodule StreamystatServer.Jellyfin.Sync.Items.Recent do
  @moduledoc """
  Handles syncing of recently added items from Jellyfin.
  """

  import Ecto.Query
  require Logger

  alias StreamystatServer.Repo
  alias StreamystatServer.Jellyfin.Client
  alias StreamystatServer.Jellyfin.Models.Item
  alias StreamystatServer.Jellyfin.Sync.Utils
  alias StreamystatServer.Jellyfin.Sync.Metrics
  alias StreamystatServer.Jellyfin.Sync.Items.Mapper
  alias StreamystatServer.Jellyfin.Sync.Items.LibraryResolver

  @doc """
  Synchronizes recently added items from a Jellyfin server.
  Only updates items if tracked fields have changed.
  """
  def sync_recently_added(server, limit \\ 20) do
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
            libraries = Utils.get_libraries_by_server(server.id)

            library_map =
              Enum.reduce(libraries, %{}, fn lib, acc ->
                Map.put(acc, lib.jellyfin_id, lib.id)
              end)

            # Process and map items with detailed error logging
            {valid_items, invalid_items} =
              Enum.reduce(items, {[], []}, fn item, {valid, invalid} ->
                try do
                  library_id = LibraryResolver.get_library_id_for_item(item, library_map, server)

                  case library_id do
                    nil ->
                      Logger.warning(
                        "Could not determine library for item #{item["Id"]} of type #{item["Type"]}"
                      )

                      {valid, [%{id: item["Id"], error: "Library not found"} | invalid]}

                    found_library_id ->
                      # Map the item with the correct library ID
                      mapped_item = Mapper.map_jellyfin_item(item, found_library_id, server.id)
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

                process_valid_items(valid_items, invalid_items, server, metrics)
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

    Metrics.log_summary(
      server.name,
      "Recently added items sync",
      updated_metrics,
      duration_ms
    )

    {result, updated_metrics}
  end

  # Private helper functions

  defp process_valid_items(valid_items, invalid_items, server, metrics) do
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
      :name, :original_title, :etag, :container, :sort_name, :premiere_date,
      :external_urls, :path, :official_rating, :overview, :genres, :community_rating,
      :runtime_ticks, :production_year, :is_folder, :parent_id, :media_type, :width,
      :height, :series_name, :series_id, :season_id, :season_name, :index_number,
      :parent_index_number, :primary_image_tag, :backdrop_image_tags, :image_blur_hashes,
      :video_type, :has_subtitles, :channel_id, :parent_backdrop_item_id,
      :parent_backdrop_image_tags, :parent_thumb_item_id, :parent_thumb_image_tag,
      :location_type, :primary_image_aspect_ratio, :series_primary_image_tag,
      :primary_image_thumb_tag, :primary_image_logo_tag
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
            if Utils.fields_changed?(existing, item, tracked_fields) do
              {inserts, [item | updates], unchanged}
            else
              {inserts, updates, [item | unchanged]}
            end
        end
      end)

    # Process insertions and updates
    {insert_result, update_result, unchanged_count} =
      do_process_item_changes(items_to_insert, items_to_update, unchanged_items, server.id, tracked_fields)

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

  defp do_process_item_changes(items_to_insert, items_to_update, unchanged_items, server_id, tracked_fields) do
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
                  i.server_id == ^server_id
            ),
            set: update_fields
          )

        count + updated
      end)

    unchanged_count = length(unchanged_items)

    {insert_result, update_result, unchanged_count}
  end
end
