# lib/streamystat_server/jellyfin/activity.ex
defmodule StreamystatServer.Activities.Models.Activity do
  use Ecto.Schema
  import Ecto.Changeset

  schema "activities" do
    field(:jellyfin_id, :integer)
    field(:name, :string)
    field(:short_overview, :string)
    field(:type, :string)
    field(:date, :utc_datetime)
    field(:severity, :string)

    field(:user_jellyfin_id, :string)
    field(:user_server_id, :integer)
    belongs_to(:user, StreamystatServer.Jellyfin.Models.User,
      foreign_key: :user_jellyfin_id,
      references: :jellyfin_id,
      define_field: false)

    belongs_to(:server, StreamystatServer.Servers.Models.Server)

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
      :user_jellyfin_id,
      :user_server_id,
      :server_id,
      :severity
    ])
    |> validate_required([:jellyfin_id, :server_id, :date])
    |> unique_constraint([:jellyfin_id, :server_id])
    |> foreign_key_constraint(:server_id)
  end
end
