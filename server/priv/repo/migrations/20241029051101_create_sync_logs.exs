defmodule StreamystatServer.Repo.Migrations.CreateSyncLogs do
  use Ecto.Migration

  def change do
    create table(:sync_logs) do
      add(:server_id, references(:servers, on_delete: :delete_all))
      add(:sync_type, :string)
      add(:synced_at, :naive_datetime)

      timestamps()
    end

    create(index(:sync_logs, [:server_id]))
    create(index(:sync_logs, [:sync_type]))
  end
end
