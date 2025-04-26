defmodule StreamystatServer.Jellyfin.Client do
  use HTTPoison.Base
  require Logger

  def process_url(url) do
    url
  end

  def process_request_headers(headers, api_key) do
    [{"X-Emby-Token", api_key} | headers]
  end

  @default_item_fields [
    "DateCreated",
    "Etag",
    "ExternalUrls",
    "Genres",
    "OriginalTitle",
    "Overview",
    "ParentId",
    "Path",
    "PrimaryImageAspectRatio",
    "ProductionYear",
    "SortName",
    "Width",
    "Height",
    "ImageTags",
    "ImageBlurHashes",
    "BackdropImageTags",
    "ParentBackdropImageTags",
    "ParentThumbImageTags",
    "SeriesThumbImageTag",
    "SeriesPrimaryImageTag",
    "Container",
    "PremiereDate",
    "CommunityRating",
    "RunTimeTicks",
    "IsFolder",
    "MediaType",
    "SeriesName",
    "SeriesId",
    "SeasonId",
    "SeasonName",
    "IndexNumber",
    "ParentIndexNumber",
    "VideoType",
    "HasSubtitles",
    "ChannelId",
    "ParentBackdropItemId",
    "ParentThumbItemId",
    "LocationType"
  ]

  def get_users(server) do
    url = "#{server.url}/Users"
    headers = process_request_headers([], server.api_key)

    case get(url, headers) do
      {:ok, %{status_code: 200, body: body}} ->
        case Jason.decode(body, keys: :strings) do
          {:ok, users} -> {:ok, users}
          {:error, decode_error} -> {:error, "JSON decode error: #{decode_error}"}
        end

      {:ok, %{status_code: status_code}} ->
        {:error, "Unexpected status code: #{status_code}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, "HTTP request failed: #{reason}"}
    end
  end

  def get_libraries(server) do
    url = "#{server.url}/Library/MediaFolders"
    headers = process_request_headers([], server.api_key)

    case get(url, headers) do
      {:ok, %{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, decoded_body} ->
            libraries =
              decoded_body
              |> Map.get("Items", [])
              |> Enum.reject(fn library ->
                library["CollectionType"] in ["boxsets", "playlists"]
              end)

            {:ok, libraries}

          {:error, _} ->
            {:error, "Failed to decode JSON response"}
        end

      {:ok, %{status_code: status_code}} ->
        {:error, "Unexpected status code: #{status_code}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, "HTTP request failed: #{reason}"}
    end
  end

  def get_item(server, item_id) do
    params = %{
      "Fields" =>
        "Path,Overview,Genres,DateCreated,MediaSources,ExternalUrls,MediaStreams,ImageTags,BackdropImageTags,ParentId,SeriesId"
    }

    try do
      case get("#{server.url}/Items/#{item_id}", server.api_key, params: params) do
        {:ok, item} when is_map(item) ->
          {:ok, item}

        {:ok, other} ->
          {:error, "Unexpected response format: #{inspect(other)}"}

        {:error, reason} ->
          {:error, reason}
      end
    rescue
      e -> {:error, "Error in get_item: #{Exception.message(e)}"}
    end
  end

  def get_library_id(server, item_id) do
    Logger.debug("Looking up library ID for item: #{item_id}")

    # First get all libraries to compare against
    case get_libraries(server) do
      {:ok, libraries} ->
        # Create a set of known library IDs for fast lookup
        library_ids = MapSet.new(libraries, fn lib -> lib["Id"] end)

        # Start the recursive lookup process
        find_library_recursive(server, item_id, library_ids)

      {:error, reason} ->
        {:error, "Failed to fetch libraries: #{inspect(reason)}"}
    end
  end

  defp find_library_recursive(server, item_id, library_ids) do
    url = "#{server.url}/Items"
    headers = process_request_headers([], server.api_key)
    params = %{Fields: "ParentId", ids: item_id}

    case get(url, headers, params: params) do
      {:ok, %{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"Items" => [item | _]}} ->
            # Check if current item is a library we know about
            if MapSet.member?(library_ids, item["Id"]) do
              # Found a matching library!
              {:ok, item["Id"]}
            else
              # Not a library - check if it has a parent
              case item do
                %{"ParentId" => nil} ->
                  # Hit the root but didn't find a library match
                  {:error, "Reached root item without finding a library match"}

                %{"ParentId" => ""} ->
                  # Empty parent ID, same as nil
                  {:error, "Reached root item without finding a library match"}

                %{"ParentId" => parent_id} ->
                  # Continue up the hierarchy
                  find_library_recursive(server, parent_id, library_ids)

                _ ->
                  {:error, "Item does not have ParentId field"}
              end
            end

          {:ok, %{"Items" => []}} ->
            {:error, "Item not found: #{item_id}"}

          {:ok, response} ->
            {:error, "Unexpected response format: #{inspect(response)}"}

          {:error, decode_error} ->
            {:error, "JSON decode error: #{inspect(decode_error)}"}
        end

      {:ok, %{status_code: status_code}} ->
        {:error, "Unexpected status code: #{status_code}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, "HTTP request failed: #{inspect(reason)}"}
    end
  end

  def get_recently_added_items(server, limit \\ 20) do
    Logger.info("Fetching recently added items from server #{server.url} with limit #{limit}")

    params = %{
      "SortBy" => "DateCreated",
      "SortOrder" => "Descending",
      "Recursive" => "true",
      "Fields" =>
        "Path,Overview,Genres,DateCreated,MediaSources,ExternalUrls,MediaStreams,ImageTags,BackdropImageTags,ParentId",
      "ImageTypeLimit" => "1",
      "EnableImageTypes" => "Primary,Backdrop,Thumb,Logo",
      "Limit" => "#{limit}"
    }

    url = "#{server.url}/Items"
    headers = process_request_headers([], server.api_key)

    Logger.debug("Making request to #{url} with params: #{inspect(params)}")

    case get(url, headers, params: params) do
      {:ok, %{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"Items" => items}} ->
            Logger.info("Successfully retrieved #{length(items)} recently added items")
            {:ok, items}

          {:ok, other} ->
            Logger.error("Unexpected response format: #{inspect(other)}")
            {:error, "Unexpected response format: #{inspect(other)}"}

          {:error, decode_error} ->
            Logger.error("JSON decode error: #{inspect(decode_error)}")
            {:error, "JSON decode error: #{inspect(decode_error)}"}
        end

      {:ok, %{status_code: status_code}} ->
        Logger.error("Unexpected status code: #{status_code}")
        {:error, "Unexpected status code: #{status_code}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("HTTP request failed: #{inspect(reason)}")
        {:error, "HTTP request failed: #{reason}"}
    end
  end

  def get_items_page(server, library_id, start_index, limit, image_types \\ nil) do
    url = "#{server.url}/Items"
    headers = process_request_headers([], server.api_key)

    params = %{
      ParentId: library_id,
      Recursive: true,
      Fields: Enum.join(@default_item_fields, ","),
      StartIndex: start_index,
      Limit: limit,
      EnableImageTypes: "Primary,Backdrop,Banner,Thumb",
      IsFolder: false,
      IsPlaceHolder: false
    }

    # Add ImageTypes parameter if provided
    params =
      if image_types do
        image_types_str =
          if is_list(image_types), do: Enum.join(image_types, ","), else: image_types

        Map.put(params, :ImageTypes, image_types_str)
      else
        params
      end

    case get(url, headers, params: params) do
      {:ok, %{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, decoded_body} ->
            # Returns {items, total_count}
            {:ok, {decoded_body["Items"] || [], decoded_body["TotalRecordCount"] || 0}}

          {:error, decode_error} ->
            Logger.error("Failed to decode items JSON: #{inspect(decode_error)}")
            {:error, "JSON decode error"}
        end

      {:ok, %{status_code: status_code}} ->
        {:error, "Unexpected status code: #{status_code}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, "HTTP request failed: #{reason}"}
    end
  end

  def get_items_with_images(
        server,
        library_id,
        start_index,
        limit,
        image_types \\ ["Primary", "Thumb", "Backdrop"]
      ) do
    get_items_page(server, library_id, start_index, limit, image_types)
  end

  def get_installed_plugins(server) do
    url = "#{server.url}/Plugins"
    headers = process_request_headers([], server.api_key)

    case get(url, headers) do
      {:ok, %{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, plugins} -> {:ok, plugins}
          {:error, decode_error} -> {:error, "JSON decode error: #{decode_error}"}
        end

      {:ok, %{status_code: status_code}} ->
        {:error, "Unexpected status code: #{status_code}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, "HTTP request failed: #{reason}"}
    end
  end

  def get_user(server, user_id) do
    url = "#{server.url}/Users/#{user_id}"
    headers = process_request_headers([], server.api_key)

    case get(url, headers) do
      {:ok, %{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, user} -> {:ok, user}
          {:error, decode_error} -> {:error, "JSON decode error: #{decode_error}"}
        end

      {:ok, %{status_code: status_code}} ->
        {:error, "Unexpected status code: #{status_code}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, "HTTP request failed: #{reason}"}
    end
  end

  def get_activities(server, start_index, limit) do
    url = "#{server.url}/System/ActivityLog/Entries"
    headers = process_request_headers([], server.api_key)
    params = [startIndex: start_index, limit: limit]

    case get(url, headers, params: params) do
      {:ok, %{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"Items" => items}} -> {:ok, items}
          {:error, decode_error} -> {:error, "JSON decode error: #{decode_error}"}
        end

      {:ok, %{status_code: status_code}} ->
        {:error, "Unexpected status code: #{status_code}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, "HTTP request failed: #{reason}"}
    end
  end
end
