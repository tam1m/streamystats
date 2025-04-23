defmodule StreamystatServer.Jellyfin.Models.User do
  use Ecto.Schema
  import Ecto.Changeset

  schema "jellyfin_users" do
    field(:jellyfin_id, :string)
    field(:name, :string)
    field(:has_password, :boolean)
    field(:has_configured_password, :boolean)
    field(:has_configured_easy_password, :boolean)
    field(:enable_auto_login, :boolean)
    field(:last_login_date, :utc_datetime)
    field(:last_activity_date, :utc_datetime)
    field(:is_administrator, :boolean)
    field(:is_hidden, :boolean)
    field(:is_disabled, :boolean)
    field(:enable_user_preference_access, :boolean)
    field(:enable_remote_control_of_other_users, :boolean)
    field(:enable_shared_device_control, :boolean)
    field(:enable_remote_access, :boolean)
    field(:enable_live_tv_management, :boolean)
    field(:enable_live_tv_access, :boolean)
    field(:enable_media_playback, :boolean)
    field(:enable_audio_playback_transcoding, :boolean)
    field(:enable_video_playback_transcoding, :boolean)
    field(:enable_playback_remuxing, :boolean)
    field(:enable_content_deletion, :boolean)
    field(:enable_content_downloading, :boolean)
    field(:enable_sync_transcoding, :boolean)
    field(:enable_media_conversion, :boolean)
    field(:enable_all_devices, :boolean)
    field(:enable_all_channels, :boolean)
    field(:enable_all_folders, :boolean)
    field(:enable_public_sharing, :boolean)
    field(:invalid_login_attempt_count, :integer)
    field(:login_attempts_before_lockout, :integer)
    field(:max_active_sessions, :integer)
    field(:remote_client_bitrate_limit, :integer)
    field(:authentication_provider_id, :string)
    field(:password_reset_provider_id, :string)
    field(:sync_play_access, :string)

    # Fix: Change this to reference the correct server model
    belongs_to(:server, StreamystatServer.Jellyfin.Models.Server)

    timestamps()
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [
      :jellyfin_id,
      :name,
      # Add server_id to the allowed fields list
      :server_id,
      :has_password,
      :has_configured_password,
      :has_configured_easy_password,
      :enable_auto_login,
      :last_login_date,
      :last_activity_date,
      :is_administrator,
      :is_hidden,
      :is_disabled,
      :enable_user_preference_access,
      :enable_remote_control_of_other_users,
      :enable_shared_device_control,
      :enable_remote_access,
      :enable_live_tv_management,
      :enable_live_tv_access,
      :enable_media_playback,
      :enable_audio_playback_transcoding,
      :enable_video_playback_transcoding,
      :enable_playback_remuxing,
      :enable_content_deletion,
      :enable_content_downloading,
      :enable_sync_transcoding,
      :enable_media_conversion,
      :enable_all_devices,
      :enable_all_channels,
      :enable_all_folders,
      :enable_public_sharing,
      :invalid_login_attempt_count,
      :login_attempts_before_lockout,
      :max_active_sessions,
      :remote_client_bitrate_limit,
      :authentication_provider_id,
      :password_reset_provider_id,
      :sync_play_access
    ])
    |> validate_required([:jellyfin_id, :name, :server_id])
    |> unique_constraint([:jellyfin_id, :server_id])
    |> foreign_key_constraint(:server_id)
  end
end
