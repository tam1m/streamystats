defmodule StreamystatServer.Repo.Migrations.AddMissingSyncTrackingToItems do
  use Ecto.Migration

  def change do
    alter table(:jellyfin_items) do
      add :missing_sync_count, :integer, default: 0
      add :first_missing_at, :utc_datetime
    end

    # Add index for performance on the query that finds items to remove
    create index(:jellyfin_items, [:server_id, :missing_sync_count, :first_missing_at])
  end
end
