defmodule StreamystatServer.Repo.Migrations.AddItemForeignKeyConstraints do
  use Ecto.Migration

  def up do
    # First ensure we have the correct indexes
    create_if_not_exists index(:playback_sessions, [:item_jellyfin_id])
    create_if_not_exists index(:activities, [:item_jellyfin_id])

    # First, we need to add a dummy record in jellyfin_items to handle orphaned references
    execute """
    INSERT INTO jellyfin_items (jellyfin_id, name, type, library_id, server_id, inserted_at, updated_at)
    VALUES ('__PLACEHOLDER_ID__', 'Placeholder Item', 'placeholder',
            (SELECT MIN(id) FROM jellyfin_libraries),
            (SELECT MIN(id) FROM servers),
            NOW(), NOW())
    ON CONFLICT (jellyfin_id) DO NOTHING
    """

    # Update orphaned references to use the placeholder
    execute """
    UPDATE playback_sessions
    SET item_jellyfin_id = '__PLACEHOLDER_ID__'
    WHERE item_jellyfin_id IS NOT NULL AND
      NOT EXISTS (SELECT 1 FROM jellyfin_items WHERE jellyfin_id = playback_sessions.item_jellyfin_id)
    """

    execute """
    UPDATE activities
    SET item_jellyfin_id = '__PLACEHOLDER_ID__'
    WHERE item_jellyfin_id IS NOT NULL AND
      NOT EXISTS (SELECT 1 FROM jellyfin_items WHERE jellyfin_id = activities.item_jellyfin_id)
    """

    # Add foreign key constraints to the playback sessions table
    alter table(:playback_sessions) do
      modify :item_jellyfin_id, references(:jellyfin_items, column: :jellyfin_id, type: :string, on_delete: :nilify_all)
    end

    # Add foreign key constraints to the activities table
    alter table(:activities) do
      modify :item_jellyfin_id, references(:jellyfin_items, column: :jellyfin_id, type: :string, on_delete: :nilify_all)
    end
  end

  def down do
    # Remove foreign key constraints from playback sessions
    drop_if_exists constraint(:playback_sessions, :playback_sessions_item_jellyfin_id_fkey)

    # Remove foreign key constraints from activities
    drop_if_exists constraint(:activities, :activities_item_jellyfin_id_fkey)

    # Restore the columns to be simple strings without constraints
    alter table(:playback_sessions) do
      modify :item_jellyfin_id, :string
    end

    alter table(:activities) do
      modify :item_jellyfin_id, :string
    end

    # Remove the placeholder item
    execute "DELETE FROM jellyfin_items WHERE jellyfin_id = '__PLACEHOLDER_ID__'"
  end
end
