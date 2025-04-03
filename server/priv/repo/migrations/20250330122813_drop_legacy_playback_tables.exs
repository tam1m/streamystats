defmodule StreamystatServer.Repo.Migrations.DropLegacyPlaybackTables do
  use Ecto.Migration

  def up do
    # Drop the old table
    drop_if_exists(table(:playback_activities))

    # Drop any indexes that might exist
    drop_if_exists(index(:playback_activities, [:server_id]))
    drop_if_exists(index(:playback_activities, [:user_id]))
    drop_if_exists(index(:playback_activities, [:rowid, :server_id]))
  end
end
