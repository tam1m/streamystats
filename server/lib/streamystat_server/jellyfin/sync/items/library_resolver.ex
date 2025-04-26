defmodule StreamystatServer.Jellyfin.Sync.Items.LibraryResolver do
  @moduledoc """
  Functions to resolve Jellyfin items to their parent libraries.
  """

  require Logger

  alias StreamystatServer.Jellyfin.Client

  @doc """
  Determines the library ID for a Jellyfin item.
  Resolution strategy:
  1. First tries to resolve based on parent ID
  2. For folder items, checks if name matches a library name
  3. Falls back to API call
  """
  def get_library_id_for_item(item, library_map, server) do
    Logger.debug(
      "Determining library for item #{item["Id"]} (#{item["Name"]}) type=#{item["Type"]}"
    )

    # First check if we already have the library directly from parent ID
    parent_id = item["ParentId"]

    cond do
      # Case 1: Parent is a library
      parent_id && Map.has_key?(library_map, parent_id) ->
        library_id = Map.get(library_map, parent_id)

        Logger.debug(
          "Found library directly from parent_id=#{parent_id} -> library_id=#{library_id}"
        )

        library_id

      # Case 2: Item is a folder and matches a library name
      item["IsFolder"] == true && match_folder_to_library(item, library_map) ->
        {library_jellyfin_id, library_id} = match_folder_to_library(item, library_map)

        Logger.debug(
          "Folder item matches library name: jellyfin_id=#{library_jellyfin_id} -> library_id=#{library_id}"
        )

        library_id

      # Case 3: API fallback
      true ->
        log_fallback_reason(item, parent_id, library_map)
        resolve_via_api(item, library_map, server)
    end
  end

  # Private functions

  defp match_folder_to_library(item, library_map) do
    item_name = item["Name"]

    # Reverse mapping: Create a map of library names to {jellyfin_id, internal_id} pairs
    # We're assuming library_map is {jellyfin_id => internal_id}
    library_name_map =
      library_map
      |> Enum.map(fn {jellyfin_id, internal_id} ->
        # Get the library name from somewhere - either metadata or inference
        # This is a placeholder as we don't have the actual library name in the given code
        library_name = get_library_name(jellyfin_id)
        {String.downcase(library_name), {jellyfin_id, internal_id}}
      end)
      |> Map.new()

    # Check if this folder's name matches a library name
    library_name_map[String.downcase(item_name)]
  end

  # Placeholder function - in real implementation, you would
  # either have library names in your library_map or fetch them
  defp get_library_name(jellyfin_id) do
    # In a real implementation, you would:
    # 1. Either have a map of {jellyfin_id => name}
    # 2. Or fetch the library name from your database
    # For now, returning a placeholder to demonstrate the concept
    "Library #{jellyfin_id}"
  end

  defp log_fallback_reason(item, parent_id, library_map) do
    cond do
      parent_id == nil ->
        Logger.debug("Item #{item["Id"]} has no parent_id, will try API method")

      !Map.has_key?(library_map, parent_id) ->
        Logger.debug("Parent #{parent_id} not found in library map, will try API method")

      true ->
        Logger.debug("Fallback to API method for other reasons")
    end
  end

  defp resolve_via_api(item, library_map, server) do
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

        Logger.debug("Item details: type=#{item["Type"]}, parent_id=#{item["ParentId"]}")
        nil
    end
  end
end
