defmodule StreamystatServer.Repo.Migrations.AddFieldsToPlaybackSessions do
  use Ecto.Migration

  def change do
    alter table(:playback_sessions) do
      add :is_paused, :boolean
      add :is_muted, :boolean
      add :volume_level, :integer
      add :audio_stream_index, :integer
      add :subtitle_stream_index, :integer
      add :media_source_id, :string
      add :repeat_mode, :string
      add :playback_order, :string
      add :remote_end_point, :string
      add :session_id, :string
      add :user_name, :string
      add :last_activity_date, :utc_datetime
      add :last_playback_check_in, :utc_datetime
      add :application_version, :string
      add :is_active, :boolean
      add :transcoding_audio_codec, :string
      add :transcoding_video_codec, :string
      add :transcoding_container, :string
      add :transcoding_is_video_direct, :boolean
      add :transcoding_is_audio_direct, :boolean
      add :transcoding_bitrate, :integer
      add :transcoding_completion_percentage, :float
      add :transcoding_width, :integer
      add :transcoding_height, :integer
      add :transcoding_audio_channels, :integer
      add :transcoding_hardware_acceleration_type, :string
      add :transcoding_reasons, {:array, :string}
    end
  end
end
