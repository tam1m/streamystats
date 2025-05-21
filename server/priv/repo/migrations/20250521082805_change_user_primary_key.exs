defmodule StreamystatServer.Repo.Migrations.ChangeUserPrimaryKey do
  use Ecto.Migration

  def up do
    # Drop foreign key constraints pointing to jellyfin_users
    execute "ALTER TABLE activities DROP CONSTRAINT IF EXISTS activities_user_id_fkey;"
    execute "ALTER TABLE playback_sessions DROP CONSTRAINT IF EXISTS playback_sessions_user_id_fkey;"
    execute "ALTER TABLE sync_logs DROP CONSTRAINT IF EXISTS sync_logs_server_id_fkey;"

    # Create a backup table
    execute "CREATE TABLE jellyfin_users_backup AS SELECT * FROM jellyfin_users;"

    # Add new columns to activities for the new relationship
    execute "ALTER TABLE activities ADD COLUMN IF NOT EXISTS user_jellyfin_id VARCHAR;"
    execute "ALTER TABLE activities ADD COLUMN IF NOT EXISTS user_server_id BIGINT;"

    # Populate new columns in activities
    execute """
    UPDATE activities a
    SET user_jellyfin_id = u.jellyfin_id, user_server_id = u.server_id
    FROM jellyfin_users u
    WHERE a.user_id = u.id;
    """

    # Update playback_sessions - add reference columns if they don't exist
    execute "ALTER TABLE playback_sessions ADD COLUMN IF NOT EXISTS user_jellyfin_id_ref VARCHAR;"
    execute "ALTER TABLE playback_sessions ADD COLUMN IF NOT EXISTS user_server_id_ref BIGINT;"

    # Populate temp columns in playback_sessions
    execute """
    UPDATE playback_sessions ps
    SET user_jellyfin_id_ref = u.jellyfin_id, user_server_id_ref = u.server_id
    FROM jellyfin_users u
    WHERE ps.user_id = u.id;
    """

    # Drop the old table and recreate it with the new primary key
    drop table(:jellyfin_users)

    create table(:jellyfin_users, primary_key: false) do
      add :jellyfin_id, :string, primary_key: true
      add :server_id, references(:servers, on_delete: :delete_all), primary_key: true
      add :name, :string, null: false
      add :has_password, :boolean
      add :has_configured_password, :boolean
      add :has_configured_easy_password, :boolean
      add :enable_auto_login, :boolean
      add :last_login_date, :utc_datetime
      add :last_activity_date, :utc_datetime
      add :is_administrator, :boolean
      add :is_hidden, :boolean
      add :is_disabled, :boolean
      add :enable_user_preference_access, :boolean
      add :enable_remote_control_of_other_users, :boolean
      add :enable_shared_device_control, :boolean
      add :enable_remote_access, :boolean
      add :enable_live_tv_management, :boolean
      add :enable_live_tv_access, :boolean
      add :enable_media_playback, :boolean
      add :enable_audio_playback_transcoding, :boolean
      add :enable_video_playback_transcoding, :boolean
      add :enable_playback_remuxing, :boolean
      add :enable_content_deletion, :boolean
      add :enable_content_downloading, :boolean
      add :enable_sync_transcoding, :boolean
      add :enable_media_conversion, :boolean
      add :enable_all_devices, :boolean
      add :enable_all_channels, :boolean
      add :enable_all_folders, :boolean
      add :enable_public_sharing, :boolean
      add :invalid_login_attempt_count, :integer
      add :login_attempts_before_lockout, :integer
      add :max_active_sessions, :integer
      add :remote_client_bitrate_limit, :integer
      add :authentication_provider_id, :string
      add :password_reset_provider_id, :string
      add :sync_play_access, :string

      timestamps()
    end

    # Copy data back from the backup table
    execute """
    INSERT INTO jellyfin_users
    (jellyfin_id, server_id, name,
    has_password, has_configured_password, has_configured_easy_password,
    enable_auto_login, last_login_date, last_activity_date, is_administrator,
    is_hidden, is_disabled, enable_user_preference_access,
    enable_remote_control_of_other_users, enable_shared_device_control,
    enable_remote_access, enable_live_tv_management, enable_live_tv_access,
    enable_media_playback, enable_audio_playback_transcoding,
    enable_video_playback_transcoding, enable_playback_remuxing,
    enable_content_deletion, enable_content_downloading,
    enable_sync_transcoding, enable_media_conversion,
    enable_all_devices, enable_all_channels, enable_all_folders,
    enable_public_sharing, invalid_login_attempt_count,
    login_attempts_before_lockout, max_active_sessions,
    remote_client_bitrate_limit, authentication_provider_id,
    password_reset_provider_id, sync_play_access, inserted_at, updated_at)
    SELECT jellyfin_id, server_id, name,
    has_password, has_configured_password, has_configured_easy_password,
    enable_auto_login, last_login_date, last_activity_date, is_administrator,
    is_hidden, is_disabled, enable_user_preference_access,
    enable_remote_control_of_other_users, enable_shared_device_control,
    enable_remote_access, enable_live_tv_management, enable_live_tv_access,
    enable_media_playback, enable_audio_playback_transcoding,
    enable_video_playback_transcoding, enable_playback_remuxing,
    enable_content_deletion, enable_content_downloading,
    enable_sync_transcoding, enable_media_conversion,
    enable_all_devices, enable_all_channels, enable_all_folders,
    enable_public_sharing, invalid_login_attempt_count,
    login_attempts_before_lockout, max_active_sessions,
    remote_client_bitrate_limit, authentication_provider_id,
    password_reset_provider_id, sync_play_access, inserted_at, updated_at
    FROM jellyfin_users_backup;
    """

    # Remove the user_id column from activities
    execute "ALTER TABLE activities DROP COLUMN IF EXISTS user_id;"

    # Add foreign key constraint to activities
    execute """
    ALTER TABLE activities
    ADD CONSTRAINT activities_user_jellyfin_id_fkey
    FOREIGN KEY (user_jellyfin_id, user_server_id)
    REFERENCES jellyfin_users (jellyfin_id, server_id)
    ON DELETE SET NULL;
    """

    # For playback_sessions: remove user_id and add new columns if they don't exist
    execute "ALTER TABLE playback_sessions DROP COLUMN IF EXISTS user_id;"
    execute "ALTER TABLE playback_sessions ADD COLUMN IF NOT EXISTS user_jellyfin_id VARCHAR;"
    execute "ALTER TABLE playback_sessions ADD COLUMN IF NOT EXISTS user_server_id BIGINT;"

    # Copy values from the temp columns
    execute """
    UPDATE playback_sessions
    SET user_jellyfin_id = user_jellyfin_id_ref, user_server_id = user_server_id_ref
    WHERE user_jellyfin_id_ref IS NOT NULL;
    """

    # Add foreign key constraint to playback_sessions
    execute """
    ALTER TABLE playback_sessions
    ADD CONSTRAINT playback_sessions_user_jellyfin_id_fkey
    FOREIGN KEY (user_jellyfin_id, user_server_id)
    REFERENCES jellyfin_users (jellyfin_id, server_id)
    ON DELETE SET NULL;
    """

    # Clean up temporary columns
    execute "ALTER TABLE playback_sessions DROP COLUMN IF EXISTS user_jellyfin_id_ref;"
    execute "ALTER TABLE playback_sessions DROP COLUMN IF EXISTS user_server_id_ref;"

    # Fix the sync_logs reference to server
    execute "ALTER TABLE sync_logs ADD CONSTRAINT sync_logs_server_id_fkey FOREIGN KEY (server_id) REFERENCES servers(id) ON DELETE CASCADE;"

    # Clean up
    execute "DROP TABLE jellyfin_users_backup;"
  end

  def down do
    raise "This migration cannot be reverted"
  end
end
