defmodule StreamystatServer.Jellyfin.PlaybackActivity do
  @derive {Jason.Encoder,
           only: [
             :id,
             :date_created,
             :rowid,
             :item_id,
             :item_type,
             :item_name,
             :client_name,
             :device_name,
             :device_id,
             :play_method,
             :play_duration,
             :play_count,
             :server_id,
             :user_id,
             :inserted_at,
             :updated_at
           ]}

  use Ecto.Schema
  import Ecto.Changeset

  schema "playback_activities" do
    field(:date_created, :naive_datetime)
    field(:rowid, :integer)
    field(:item_id, :string)
    field(:item_type, :string)
    field(:item_name, :string)
    field(:client_name, :string)
    field(:device_name, :string)
    field(:device_id, :string)
    field(:play_method, :string)
    field(:play_duration, :integer)
    field(:play_count, :integer)

    belongs_to(:server, StreamystatServer.Servers.Server)
    belongs_to(:user, StreamystatServer.Jellyfin.User)

    timestamps()
  end

  def changeset(playback_activity, attrs) do
    playback_activity
    |> cast(attrs, [
      :date_created,
      :rowid,
      :item_id,
      :item_type,
      :item_name,
      :client_name,
      :device_name,
      :device_id,
      :play_method,
      :play_duration,
      :play_count,
      :server_id,
      :user_id
    ])
    |> validate_required([:date_created, :rowid, :item_id, :server_id, :user_id])
    |> unique_constraint([:rowid, :server_id])
    |> foreign_key_constraint(:user_id)
  end
end
