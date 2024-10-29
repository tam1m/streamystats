defmodule StreamystatServer.Jellyfin.User do
  use Ecto.Schema
  import Ecto.Changeset

  schema "jellyfin_users" do
    field(:jellyfin_id, :string)
    field(:name, :string)
    belongs_to(:server, StreamystatServer.Servers.Server)
    has_many(:playback_activities, StreamystatServer.Jellyfin.PlaybackActivity)

    timestamps()
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:jellyfin_id, :name, :server_id])
    |> validate_required([:jellyfin_id, :name, :server_id])
    |> unique_constraint([:jellyfin_id, :server_id])
    |> foreign_key_constraint(:server_id)
  end
end
