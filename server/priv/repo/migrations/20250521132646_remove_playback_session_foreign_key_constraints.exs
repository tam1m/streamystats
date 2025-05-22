defmodule StreamystatServer.Repo.Migrations.RemovePlaybackSessionForeignKeyConstraints do
  use Ecto.Migration

  def up do
    # Remove foreign key constraint from playback_sessions
    drop constraint(:playback_sessions, :playback_sessions_item_jellyfin_id_fkey)

    # Modify the column to be a string without constraints
    alter table(:playback_sessions) do
      modify :item_jellyfin_id, :string
    end
  end

  def down do
    # Add the foreign key constraint back to playback_sessions
    alter table(:playback_sessions) do
      modify :item_jellyfin_id, references(:jellyfin_items, column: :jellyfin_id, type: :string, on_delete: :nilify_all)
    end
  end
end
