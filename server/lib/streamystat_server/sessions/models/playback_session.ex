defmodule StreamystatServer.Sessions.Models.PlaybackSession do
  use Ecto.Schema
  import Ecto.Changeset

  @derive {Jason.Encoder,
           only: [
             :id,
             :user_jellyfin_id,
             :device_id,
             :device_name,
             :client_name,
             :item_jellyfin_id,
             :item_name,
             :series_jellyfin_id,
             :series_name,
             :season_jellyfin_id,
             :play_duration,
             :play_method,
             :start_time,
             :end_time,
             :position_ticks,
             :runtime_ticks,
             :percent_complete,
             :completed,
             :user_id,
             :server_id,
             :is_paused,
             :is_muted,
             :volume_level,
             :audio_stream_index,
             :subtitle_stream_index,
             :media_source_id,
             :repeat_mode,
             :playback_order,
             :remote_end_point,
             :session_id,
             :user_name,
             :last_activity_date,
             :last_playback_check_in,
             :application_version,
             :is_active,
             :transcoding_audio_codec,
             :transcoding_video_codec,
             :transcoding_container,
             :transcoding_is_video_direct,
             :transcoding_is_audio_direct,
             :transcoding_bitrate,
             :transcoding_completion_percentage,
             :transcoding_width,
             :transcoding_height,
             :transcoding_audio_channels,
             :transcoding_hardware_acceleration_type,
             :transcoding_reasons,
             :inserted_at,
             :updated_at
           ]}

  schema "playback_sessions" do
    field(:user_jellyfin_id, :string)
    field(:device_id, :string)
    field(:device_name, :string)
    field(:client_name, :string)
    field(:item_jellyfin_id, :string)
    field(:item_name, :string)
    field(:series_jellyfin_id, :string)
    field(:series_name, :string)
    field(:season_jellyfin_id, :string)
    field(:play_duration, :integer)
    field(:play_method, :string)
    field(:start_time, :utc_datetime)
    field(:end_time, :utc_datetime)
    field(:position_ticks, :integer)
    field(:runtime_ticks, :integer)
    field(:percent_complete, :float)
    field(:completed, :boolean)

    # New PlayState fields
    field(:is_paused, :boolean)
    field(:is_muted, :boolean)
    field(:volume_level, :integer)
    field(:audio_stream_index, :integer)
    field(:subtitle_stream_index, :integer)
    field(:media_source_id, :string)
    field(:repeat_mode, :string)
    field(:playback_order, :string)

    # New Session fields
    field(:remote_end_point, :string)
    # This maps to "Id" in the Session object
    field(:session_id, :string)
    field(:user_name, :string)
    field(:last_activity_date, :utc_datetime)
    field(:last_playback_check_in, :utc_datetime)
    field(:application_version, :string)
    field(:is_active, :boolean)

    # Transcoding info fields
    field(:transcoding_audio_codec, :string)
    field(:transcoding_video_codec, :string)
    field(:transcoding_container, :string)
    field(:transcoding_is_video_direct, :boolean)
    field(:transcoding_is_audio_direct, :boolean)
    field(:transcoding_bitrate, :integer)
    field(:transcoding_completion_percentage, :float)
    field(:transcoding_width, :integer)
    field(:transcoding_height, :integer)
    field(:transcoding_audio_channels, :integer)
    field(:transcoding_hardware_acceleration_type, :string)
    field(:transcoding_reasons, {:array, :string})

    belongs_to(:user, StreamystatServer.Jellyfin.Models.User)
    belongs_to(:server, StreamystatServer.Servers.Models.Server)

    timestamps()
  end

  def changeset(playback_session, attrs) do
    playback_session
    |> cast(attrs, [
      :user_jellyfin_id,
      :device_id,
      :device_name,
      :client_name,
      :item_jellyfin_id,
      :item_name,
      :series_jellyfin_id,
      :series_name,
      :season_jellyfin_id,
      :play_duration,
      :play_method,
      :start_time,
      :end_time,
      :position_ticks,
      :runtime_ticks,
      :percent_complete,
      :completed,
      :user_id,
      :server_id,
      # New fields
      :is_paused,
      :is_muted,
      :volume_level,
      :audio_stream_index,
      :subtitle_stream_index,
      :media_source_id,
      :repeat_mode,
      :playback_order,
      :remote_end_point,
      :session_id,
      :user_name,
      :last_activity_date,
      :last_playback_check_in,
      :application_version,
      :is_active,
      :transcoding_audio_codec,
      :transcoding_video_codec,
      :transcoding_container,
      :transcoding_is_video_direct,
      :transcoding_is_audio_direct,
      :transcoding_bitrate,
      :transcoding_completion_percentage,
      :transcoding_width,
      :transcoding_height,
      :transcoding_audio_channels,
      :transcoding_hardware_acceleration_type,
      :transcoding_reasons
    ])
    |> validate_required([
      :user_jellyfin_id,
      :item_jellyfin_id,
      :play_duration,
      :start_time,
      :server_id
    ])
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:server_id)
  end
end
