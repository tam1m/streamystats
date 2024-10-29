defmodule StreamystatServer.Jellyfin.Item do
  use Ecto.Schema
  import Ecto.Changeset
  alias StreamystatServer.Servers.Server
  alias StreamystatServer.Jellyfin.Library

  schema "jellyfin_items" do
    field(:jellyfin_id, :string)
    field(:name, :string)
    field(:type, :string)
    belongs_to(:library, Library)
    belongs_to(:server, Server)

    timestamps()
  end

  def changeset(item, attrs) do
    item
    |> cast(attrs, [:jellyfin_id, :name, :type, :library_id, :server_id])
    |> validate_required([:jellyfin_id, :name, :type, :library_id, :server_id])
    |> unique_constraint([:jellyfin_id, :library_id])
    |> foreign_key_constraint(:library_id)
    |> foreign_key_constraint(:server_id)
  end
end
