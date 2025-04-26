defmodule StreamystatServer.Jellyfin.Sync.Items.LibraryResolver do
  @moduledoc """
  Functions to resolve Jellyfin items to their parent libraries.
  """

  require Logger

  alias StreamystatServer.Jellyfin.Client

  @doc """
  Determines the library ID for a Jellyfin item.
  First tries to resolve based on parent ID, then falls back to API call.
  """
  def get_library_id_for_item(item, library_map, server) do
    Logger.debug(
      "Determining library for item #{item["Id"]} (#{item["Name"]}) type=#{item["Type"]}"
    )

    # First check if we already have the library directly from parent ID
    parent_id = item["ParentId"]

    if parent_id && Map.has_key?(library_map, parent_id) do
      # If the parent is a library, use it directly
      library_id = Map.get(library_map, parent_id)

      Logger.debug(
        "Found library directly from parent_id=#{parent_id} -> library_id=#{library_id}"
      )

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
            Logger.debug(
              "API returned library_jellyfin_id=#{library_jellyfin_id} -> library_id=#{library_id}"
            )

            library_id
          else
            Logger.warning(
              "API returned library_jellyfin_id=#{library_jellyfin_id}, but no matching DB library found"
            )

            nil
          end

        {:error, reason} ->
          Logger.warning(
            "Could not determine library for item #{item["Id"]} (#{item["Name"]}): #{inspect(reason)}"
          )

          Logger.debug("Item details: type=#{item["Type"]}, parent_id=#{parent_id}")
          nil
      end
    end
  end
end
