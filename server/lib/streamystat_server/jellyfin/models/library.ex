defmodule StreamystatServer.Jellyfin.Models.Library do
  use Ecto.Schema
  import Ecto.Changeset

  schema "jellyfin_libraries" do
    field(:jellyfin_id, :string)
    field(:name, :string)
    field(:type, :string)
    belongs_to(:server, StreamystatServer.Jellyfin.Models.User)

    timestamps()
  end

  def changeset(library, attrs) do
    library
    |> cast(attrs, [:jellyfin_id, :name, :type, :server_id])
    |> validate_required([:jellyfin_id, :name, :type, :server_id])
    |> unique_constraint([:jellyfin_id, :server_id])
    |> foreign_key_constraint(:server_id)
  end
end
