defmodule StreamystatServer.Repo.Migrations.AddFieldsToSyncLogs do
  use Ecto.Migration

  def change do
    alter table(:sync_logs) do
      add(:sync_started_at, :naive_datetime)
      add(:sync_completed_at, :naive_datetime)
      add(:status, :string)
      remove(:synced_at)
    end
  end
end
