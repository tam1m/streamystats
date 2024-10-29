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

  def get_recently_added(server, limit \\ 20) do
    url = "#{server.url}/Users/#{server.admin_id}/Items/Latest"
    headers = process_request_headers([], server.api_key)

    params = %{
      Limit: limit,
      Fields: "MediaSources,DateCreated"
    }

    case get(url, headers, params: params) do
      {:ok, %{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, items} ->
            filtered_items = Enum.filter(items, fn item -> item["LocationType"] != "Virtual" end)
            {:ok, filtered_items}

          {:error, decode_error} ->
            Logger.error("Failed to decode JSON response: #{inspect(decode_error)}")
            {:error, "Failed to decode JSON response"}
        end

      {:ok, %{status_code: status_code}} ->
        Logger.error("Unexpected status code: #{status_code}")
        {:error, "Unexpected status code: #{status_code}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("HTTP request failed: #{inspect(reason)}")
        {:error, "HTTP request failed: #{inspect(reason)}"}
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

    params = %{
      ParentId: library_id,
      Recursive: true,
      Fields: "Path"
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

  def get_playback_stats(server, oldest_activity_date) do
    url = "#{server.url}/user_usage_stats/submit_custom_query"

    headers = [
      {"accept", "application/json"},
      {"content-type", "application/json"},
      {"authorization",
       "MediaBrowser Client=\"Jellyfin Web\", Device=\"Elixir\", DeviceId=\"StreamystatServer\", Version=\"1.0.0\", Token=\"#{server.api_key}\""}
    ]

    query = build_playback_query(oldest_activity_date, server.last_synced_playback_id)

    body =
      Jason.encode!(%{
        "CustomQueryString" => query,
        "ReplaceUserId" => true
      })

    params = [stamp: :os.system_time(:millisecond)]

    Logger.info("Sending request to #{url} with params: #{inspect(params)} and body: #{body}")

    case post(url, body, headers, params: params) do
      {:ok, %HTTPoison.Response{status_code: 200, body: response_body}} ->
        case Jason.decode(response_body) do
          {:ok, %{"results" => results}} when is_list(results) ->
            Logger.info("Successfully retrieved playback stats: #{inspect(results)}")
            {:ok, results}

          {:ok, decoded_body} ->
            Logger.warning("Unexpected response format: #{inspect(decoded_body)}")
            {:error, :unexpected_format}

          {:error, decode_error} ->
            Logger.error("Failed to decode JSON response: #{inspect(decode_error)}")
            {:error, "Failed to decode JSON response"}
        end

      {:ok, %HTTPoison.Response{status_code: status_code}} ->
        Logger.error("Unexpected status code: #{status_code}")
        {:error, "Unexpected status code: #{status_code}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("HTTP request failed: #{inspect(reason)}")
        {:error, "HTTP request failed: #{inspect(reason)}"}
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

  defp build_playback_query(oldest_activity_date, last_synced_id) do
    conditions = []

    conditions =
      if oldest_activity_date do
        ["DateCreated >= '#{NaiveDateTime.to_string(oldest_activity_date)}'"] ++ conditions
      else
        conditions
      end

    conditions =
      if last_synced_id && last_synced_id > 0 do
        ["ROWID > #{last_synced_id}"] ++ conditions
      else
        conditions
      end

    where_clause =
      if length(conditions) > 0, do: "WHERE " <> Enum.join(conditions, " AND ") <> "\n", else: ""

    """
    SELECT ROWID, *
    FROM PlaybackActivity
    #{where_clause}ORDER BY ROWID ASC
    LIMIT 1000
    """
  end
end
