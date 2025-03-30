defmodule StreamystatServer.JellyfinSync do
  alias StreamystatServer.Repo
  alias StreamystatServer.JellyfinClient
  alias StreamystatServer.Jellyfin.Library
  alias StreamystatServer.Jellyfin.Item
  alias StreamystatServer.Jellyfin.User
  alias StreamystatServer.Jellyfin.Activity
  require Logger

  def sync_users(server) do
    Logger.info("Starting user sync for server #{server.name}")

    case JellyfinClient.get_users(server) do
      {:ok, jellyfin_users} ->
        users_data = Enum.map(jellyfin_users, &map_jellyfin_user(&1, server.id))

        Repo.transaction(fn ->
          {count, _} =
            Repo.insert_all(
              StreamystatServer.Jellyfin.User,
              users_data,
              on_conflict: {:replace, [:name]},
              conflict_target: [:jellyfin_id, :server_id]
            )

          count
        end)
        |> case do
          {:ok, count} ->
            Logger.info("Successfully synced #{count} users for server #{server.name}")
            {:ok, count}

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

    case JellyfinClient.get_libraries(server) do
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

  def sync_items(server) do
    Logger.info("Starting item sync for all libraries")

    case JellyfinClient.get_libraries(server) do
      {:ok, libraries} ->
        results =
          Enum.map(libraries, fn library ->
            sync_library_items(server, library["Id"])
          end)

        total_count = Enum.sum(Enum.map(results, fn {_, count, _} -> count end))
        total_errors = Enum.flat_map(results, fn {_, _, errors} -> errors end)

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
        Logger.error("Failed to fetch libraries: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def sync_activities(server, batch_size \\ 5000) do
    Logger.info("Starting full activity sync for server #{server.name}")
    result = sync_activities_batch(server, 0, batch_size, 0)
    Logger.info("Finished full activity sync for server #{server.name}")
    result
  end

  def sync_recent_activities(server) do
    Logger.info("Starting recent activity sync for server #{server.name}")

    result =
      case JellyfinClient.get_activities(server, 0, 25) do
        {:ok, activities} ->
          new_activities = Enum.map(activities, &map_activity(&1, server))
          {inserted, _} = Repo.insert_all(Activity, new_activities, on_conflict: :nothing)
          {:ok, inserted}

        {:error, reason} ->
          {:error, reason}
      end

    Logger.info("Finished recent activity sync for server #{server.name}")
    result
  end

  defp sync_activities_batch(server, start_index, batch_size, total_synced) do
    case JellyfinClient.get_activities(server, start_index, batch_size) do
      {:ok, []} ->
        {:ok, total_synced}

      {:ok, activities} ->
        new_activities = Enum.map(activities, &map_activity(&1, server))
        {inserted, _} = Repo.insert_all(Activity, new_activities, on_conflict: :nothing)

        if length(activities) < batch_size do
          {:ok, total_synced + inserted}
        else
          sync_activities_batch(
            server,
            start_index + batch_size,
            batch_size,
            total_synced + inserted
          )
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Add sanitization helper functions at the top
  defp sanitize_string(nil), do: nil

  defp sanitize_string(str) when is_binary(str) do
    str
    # Remove null bytes
    |> String.replace(<<0>>, "")
    # Remove control characters
    |> String.replace(~r/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/, "")
  end

  defp sanitize_string(other), do: other

  # Add retry mechanism for HTTP requests
  defp with_retry(fun, attempts \\ 3, delay \\ 1000) do
    try do
      fun.()
    rescue
      e ->
        if attempts > 1 do
          Logger.warning(
            "Request failed, retrying in #{delay}ms... (#{attempts - 1} attempts left)"
          )

          Process.sleep(delay)
          with_retry(fun, attempts - 1, delay * 2)
        else
          Logger.error("Request failed after all retry attempts: #{inspect(e)}")
          {:error, e}
        end
    end
  end

  defp sync_library_items(server, jellyfin_library_id) do
    Logger.info("Starting item sync for Jellyfin library #{jellyfin_library_id}")

    with {:ok, library} <- get_library_by_jellyfin_id(jellyfin_library_id, server.id),
         {:ok, jellyfin_items} <-
           with_retry(fn -> JellyfinClient.get_items(server, jellyfin_library_id) end) do
      items = Enum.map(jellyfin_items, &map_jellyfin_item(&1, library.id, server.id))

      try do
        # Insert items in batches of 1000
        {total_count, errors} =
          Enum.chunk_every(items, 1000)
          |> Enum.reduce({0, []}, fn batch, {acc_count, acc_errors} ->
            case Repo.insert_all(
                   Item,
                   batch,
                   on_conflict: {:replace_all_except, [:id]},
                   conflict_target: [:jellyfin_id, :library_id]
                 ) do
              {count, nil} -> {acc_count + count, acc_errors}
              {_, error} -> {acc_count, [error | acc_errors]}
            end
          end)

        case errors do
          [] ->
            Logger.info("Synced #{total_count} items for library #{library.name}")
            {:ok, total_count, []}

          _ ->
            Logger.warning(
              "Synced #{total_count} items for library #{library.name} with #{length(errors)} errors"
            )

            {:partial, total_count, errors}
        end
      rescue
        e ->
          Logger.error("Error syncing items for library #{library.name}: #{inspect(e)}")
          {:error, 0, [inspect(e)]}
      end
    else
      {:error, :library_not_found} ->
        Logger.error(
          "Library with Jellyfin ID #{jellyfin_library_id} not found for server #{server.id}"
        )

        {:error, 0, ["Library not found"]}

      {:error, reason} ->
        Logger.error(
          "Failed to sync items for Jellyfin library #{jellyfin_library_id}: #{inspect(reason)}"
        )

        {:error, 0, [inspect(reason)]}
    end
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
    %{
      jellyfin_id: jellyfin_item["Id"],
      name: sanitize_string(jellyfin_item["Name"]),
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
      series_primary_image_tag: sanitize_string(jellyfin_item["SeriesPrimaryImageTag"]),
      season_name: sanitize_string(jellyfin_item["SeasonName"]),
      series_studio: sanitize_string(jellyfin_item["SeriesStudio"]),
      index_number: jellyfin_item["IndexNumber"],
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

    %{
      jellyfin_id: jellyfin_library["Id"],
      name: sanitize_string(jellyfin_library["Name"]),
      type: sanitize_string(type),
      server_id: server_id,
      inserted_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second),
      updated_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
    }
  end
end
