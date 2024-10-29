defmodule StreamystatServer.Servers.Server do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer() | nil,
          name: String.t(),
          url: String.t(),
          api_key: String.t(),
          admin_id: String.t(),
          last_synced_playback_id: integer(),
          inserted_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil
        }

  schema "servers" do
    field(:name, :string)
    field(:url, :string)
    field(:api_key, :string)
    field(:admin_id, :string)
    field(:last_synced_playback_id, :integer, default: 0)

    timestamps()
  end

  def changeset(server, attrs) do
    server
    |> cast(attrs, [:name, :url, :api_key, :admin_id])
    |> validate_required([:name, :url, :api_key, :admin_id])
    |> unique_constraint(:name)
  end
end
