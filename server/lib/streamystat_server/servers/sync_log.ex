defmodule StreamystatServer.Servers.SyncLog do
  use Ecto.Schema
  import Ecto.Changeset

  schema "sync_logs" do
    field(:sync_type, :string)
    field(:sync_started_at, :naive_datetime)
    field(:sync_completed_at, :naive_datetime)
    field(:status, :string)
    belongs_to(:server, StreamystatServer.Servers.Server)

    timestamps()
  end

  @doc false
  def changeset(sync_log, attrs) do
    sync_log
    |> cast(attrs, [:server_id, :sync_type, :sync_started_at, :sync_completed_at, :status])
    |> validate_required([:server_id, :sync_type, :sync_started_at])
  end
end
