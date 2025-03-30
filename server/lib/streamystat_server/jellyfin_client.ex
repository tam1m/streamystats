defmodule StreamystatServer.JellyfinClient do
  use HTTPoison.Base
  require Logger

  def process_url(url) do
    url
  end

  def process_request_headers(headers, api_key) do
    [{"X-Emby-Token", api_key} | headers]
  end

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

  def get_items(server, library_id) do
    url = "#{server.url}/Items"
    headers = process_request_headers([], server.api_key)

    fields = [
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
      "Height"
    ]

    params = %{
      ParentId: library_id,
      Recursive: true,
      Fields: Enum.join(fields, ",")
    }

    case get(url, headers, params: params) do
      {:ok, %{status_code: 200, body: body}} ->
        decoded_body = Jason.decode!(body)
        {:ok, decoded_body["Items"]}

      {:ok, %{status_code: status_code}} ->
        {:error, "Unexpected status code: #{status_code}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, "HTTP request failed: #{reason}"}
    end
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
