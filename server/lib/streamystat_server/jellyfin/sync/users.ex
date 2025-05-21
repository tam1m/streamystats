defmodule StreamystatServer.Jellyfin.Sync.Users do
  @moduledoc """
  Handles synchronization of Jellyfin users to the local database.
  """

  import Ecto.Query
  require Logger

  alias StreamystatServer.Repo
  alias StreamystatServer.Jellyfin.Client
  alias StreamystatServer.Jellyfin.Models.User
  alias StreamystatServer.Jellyfin.Sync.Utils

  @doc """
  Synchronizes users from a Jellyfin server to the local database.
  Returns {:ok, %{updated: count, deleted: count}} on success.
  """
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
              User,
              users_data,
              on_conflict: {:replace,
                [
                 :name, :has_password, :has_configured_password, :has_configured_easy_password,
                 :enable_auto_login, :last_login_date, :last_activity_date, :is_administrator,
                 :is_hidden, :is_disabled, :enable_user_preference_access,
                 :enable_remote_control_of_other_users, :enable_shared_device_control,
                 :enable_remote_access, :enable_live_tv_management, :enable_live_tv_access,
                 :enable_media_playback, :enable_audio_playback_transcoding, :enable_video_playback_transcoding,
                 :enable_playback_remuxing, :enable_content_deletion, :enable_content_downloading,
                 :enable_sync_transcoding, :enable_media_conversion, :enable_all_devices,
                 :enable_all_channels, :enable_all_folders, :enable_public_sharing,
                 :invalid_login_attempt_count, :login_attempts_before_lockout, :max_active_sessions,
                 :remote_client_bitrate_limit, :authentication_provider_id, :password_reset_provider_id,
                 :sync_play_access, :updated_at
                ]},
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

  @doc """
  Maps a Jellyfin user JSON object to a map suitable for database insertion.
  """
  def map_jellyfin_user(user_data, server_id) do
    %{
      jellyfin_id: user_data["Id"],
      name: user_data["Name"],
      server_id: server_id,
      has_password: user_data["HasPassword"],
      has_configured_password: user_data["HasConfiguredPassword"],
      has_configured_easy_password: user_data["HasConfiguredEasyPassword"],
      enable_auto_login: user_data["EnableAutoLogin"],
      last_login_date: Utils.parse_datetime_to_utc(user_data["LastLoginDate"]),
      last_activity_date: Utils.parse_datetime_to_utc(user_data["LastActivityDate"]),
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
end
