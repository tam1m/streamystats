# lib/streamystat_server/jellyfin/activity.ex
defmodule StreamystatServer.Activities.Models.Activity do
  use Ecto.Schema
  import Ecto.Changeset
  alias StreamystatServer.Jellyfin.Models.Item
  alias StreamystatServer.Jellyfin.Models.User
  alias StreamystatServer.Servers.Models.Server

  @primary_key {:jellyfin_id, :integer, []}
  @primary_key_server_field :server_id
  schema "activities" do
    field(:name, :string)
    field(:short_overview, :string)
    field(:type, :string)
    field(:date, :utc_datetime)
    field(:severity, :string)
    field(:item_jellyfin_id, :string)

    field(:user_jellyfin_id, :string)
    field(:user_server_id, :integer)
    belongs_to(:user, User,
      foreign_key: :user_jellyfin_id,
      references: :jellyfin_id,
      define_field: false)

    belongs_to(:item, Item,
      foreign_key: :item_jellyfin_id,
      references: :jellyfin_id,
      define_field: false)

    belongs_to(:server, Server, primary_key: true)

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
      :severity,
      :item_jellyfin_id
    ])
    |> validate_required([:jellyfin_id, :server_id, :date])
    |> unique_constraint([:jellyfin_id, :server_id], name: "activities_pkey")
    |> foreign_key_constraint(:server_id)
    |> foreign_key_constraint(:item_jellyfin_id)
  end
end
