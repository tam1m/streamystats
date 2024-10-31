defmodule StreamystatServer.Repo.Migrations.AddMoreUserFields do
  use Ecto.Migration

  def change do
    alter table(:jellyfin_users) do
      add(:has_password, :boolean)
      add(:has_configured_password, :boolean)
      add(:has_configured_easy_password, :boolean)
      add(:enable_auto_login, :boolean)
      add(:last_login_date, :naive_datetime)
      add(:last_activity_date, :naive_datetime)
      add(:is_administrator, :boolean)
      add(:is_hidden, :boolean)
      add(:is_disabled, :boolean)
      add(:enable_user_preference_access, :boolean)
      add(:enable_remote_control_of_other_users, :boolean)
      add(:enable_shared_device_control, :boolean)
      add(:enable_remote_access, :boolean)
      add(:enable_live_tv_management, :boolean)
      add(:enable_live_tv_access, :boolean)
      add(:enable_media_playback, :boolean)
      add(:enable_audio_playback_transcoding, :boolean)
      add(:enable_video_playback_transcoding, :boolean)
      add(:enable_playback_remuxing, :boolean)
      add(:enable_content_deletion, :boolean)
      add(:enable_content_downloading, :boolean)
      add(:enable_sync_transcoding, :boolean)
      add(:enable_media_conversion, :boolean)
      add(:enable_all_devices, :boolean)
      add(:enable_all_channels, :boolean)
      add(:enable_all_folders, :boolean)
      add(:enable_public_sharing, :boolean)
      add(:invalid_login_attempt_count, :integer)
      add(:login_attempts_before_lockout, :integer)
      add(:max_active_sessions, :integer)
      add(:remote_client_bitrate_limit, :integer)
      add(:authentication_provider_id, :string)
      add(:password_reset_provider_id, :string)
      add(:sync_play_access, :string)
    end
  end
end
