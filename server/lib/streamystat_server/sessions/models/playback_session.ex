# server/lib/streamystat_server/jellyfin/playback_session.ex
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
      :server_id
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
