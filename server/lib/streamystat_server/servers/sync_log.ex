defmodule StreamystatServer.Servers.SyncLog do
  use Ecto.Schema
  import Ecto.Changeset

  schema "sync_logs" do
    field(:sync_type, :string)
    field(:synced_at, :naive_datetime)
    belongs_to(:server, StreamystatServer.Servers.Server)

    timestamps()
  end

  def changeset(sync_log, attrs) do
    sync_log
    |> cast(attrs, [:server_id, :sync_type, :synced_at])
    |> validate_required([:server_id, :sync_type, :synced_at])
  end
end
