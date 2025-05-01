defmodule StreamystatServer.Jellyfin.Sync.Items.ImageRefresh do
  @moduledoc """
  Handles refreshing images for specific Jellyfin items.
  """

  require Logger
  import Ecto.Query
  alias StreamystatServer.Repo
  alias StreamystatServer.Jellyfin.Models.Item
  alias StreamystatServer.Jellyfin.Client
  alias StreamystatServer.Jellyfin.Sync.Items.Mapper
  alias StreamystatServer.Jellyfin.Sync.Utils

  @doc """
  Refreshes images for a specific item by its Jellyfin ID.
  Returns {:ok, updated_item} or {:error, reason}.
  """
  def refresh_item_images(server, jellyfin_id) do
    Logger.info("Refreshing images for item #{jellyfin_id}")

    with {:ok, item} <- get_item_by_jellyfin_id(jellyfin_id, server.id),
         {:ok, jellyfin_item} <- fetch_item_from_jellyfin(server, jellyfin_id),
         mapped_item <- Mapper.map_jellyfin_item(jellyfin_item, item.library_id, server.id),
         {:ok, updated_item} <- update_item_images(item, mapped_item) do
      {:ok, updated_item}
    else
      {:error, reason} ->
        Logger.error("Failed to refresh images for item #{jellyfin_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Refreshes images for multiple items by their Jellyfin IDs.
  Returns {:ok, {updated_count, failed_ids}} or {:error, reason}.
  """
  def refresh_items_images(server, jellyfin_ids) when is_list(jellyfin_ids) do
    Logger.info("Refreshing images for #{length(jellyfin_ids)} items")

    results =
      Enum.reduce(jellyfin_ids, {0, []}, fn jellyfin_id, {success_count, failed_ids} ->
        case refresh_item_images(server, jellyfin_id) do
          {:ok, _} -> {success_count + 1, failed_ids}
          {:error, _} -> {success_count, [jellyfin_id | failed_ids]}
        end
      end)

    case results do
      {0, failed_ids} -> {:error, "Failed to refresh any items: #{inspect(failed_ids)}"}
      {count, []} -> {:ok, {count, []}}
      {count, failed_ids} -> {:ok, {count, failed_ids}}
    end
  end

  # Private helper functions

  defp get_item_by_jellyfin_id(jellyfin_id, server_id) do
    case Repo.get_by(Item, jellyfin_id: jellyfin_id, server_id: server_id) do
      nil -> {:error, :item_not_found}
      item -> {:ok, item}
    end
  end

  defp fetch_item_from_jellyfin(server, jellyfin_id) do
    case Client.get_item(server, jellyfin_id) do
      {:ok, item} -> {:ok, item}
      {:error, reason} -> {:error, reason}
    end
  end

  defp update_item_images(existing_item, new_item) do
    # Only update image-related fields
    image_fields = [
      :primary_image_tag,
      :backdrop_image_tags,
      :primary_image_thumb_tag,
      :primary_image_logo_tag,
      :image_blur_hashes,
      :parent_backdrop_image_tags,
      :parent_thumb_image_tag,
      :series_primary_image_tag,
      :etag
    ]

    changeset =
      existing_item
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.put_change(:updated_at, NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second))

    # Add each image field to the changeset if it has changed
    changeset =
      Enum.reduce(image_fields, changeset, fn field, acc ->
        if Map.get(existing_item, field) != Map.get(new_item, field) do
          Ecto.Changeset.put_change(acc, field, Map.get(new_item, field))
        else
          acc
        end
      end)

    case Repo.update(changeset) do
      {:ok, updated_item} -> {:ok, updated_item}
      {:error, changeset} -> {:error, changeset}
    end
  end
end 