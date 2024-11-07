# lib/streamystat_server/jellyfin/activity.ex
defmodule StreamystatServer.Jellyfin.Activity do
  use Ecto.Schema
  import Ecto.Changeset

  schema "activities" do
    field(:jellyfin_id, :integer)
    field(:name, :string)
    field(:short_overview, :string)
    field(:type, :string)
    field(:date, :utc_datetime)
    field(:severity, :string)

    belongs_to(:user, StreamystatServer.Jellyfin.User)
    belongs_to(:server, StreamystatServer.Servers.Server)

    timestamps()
  end

  def changeset(activity, attrs) do
    activity
    |> cast(attrs, [
      :jellyfin_id,
      :name,
      :short_overview,
      :type,
      :date,
      :user_id,
      :server_id,
      :severity
    ])
    |> validate_required([:jellyfin_id, :server_id, :date])
    |> unique_constraint([:jellyfin_id, :server_id])
  end
end
