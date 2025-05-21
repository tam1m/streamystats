defmodule StreamystatServer.Repo.Migrations.ChangeItemPrimaryKeyToJellyfinId do
  use Ecto.Migration

  def up do
    # Step 1: Ensure jellyfin_id is not null and has no duplicates
    execute "UPDATE jellyfin_items SET jellyfin_id = id::text || '_temp' WHERE jellyfin_id IS NULL"
    execute "CREATE UNIQUE INDEX idx_unique_jellyfin_id ON jellyfin_items (jellyfin_id)"

    # Step 2: Add necessary new foreign key columns to related tables

    # For playback_sessions
    execute "CREATE INDEX IF NOT EXISTS idx_playback_sessions_jellyfin_id ON playback_sessions (item_jellyfin_id)"

    # For activities
    alter table(:activities) do
      # Add jellyfin_id reference if needed
      add_if_not_exists :item_jellyfin_id, :string
    end

    # Check if item_id column exists before trying to update
    execute """
    DO $$
    BEGIN
      IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_name = 'activities' AND column_name = 'item_id'
      ) THEN
        UPDATE activities SET item_jellyfin_id = item_id WHERE item_jellyfin_id IS NULL AND item_id IS NOT NULL;
      END IF;
    END $$;
    """

    execute "CREATE INDEX IF NOT EXISTS idx_activities_item_jellyfin_id ON activities (item_jellyfin_id)"

    # Step 3: Drop the primary key constraint from jellyfin_items
    execute "ALTER TABLE jellyfin_items DROP CONSTRAINT jellyfin_items_pkey"

    # Step 4: Add a new primary key constraint on jellyfin_id
    execute "ALTER TABLE jellyfin_items ADD PRIMARY KEY (jellyfin_id)"

    # Step 5: Update jellyfin_id to be the new UUID primary key field
    alter table(:jellyfin_items) do
      remove :id
    end

    # Step 6: Update references in code (columns and indexes)
    # These will be handled separately in schema files
  end

  def down do
    # Step 1: Add back the id column with sequence
    alter table(:jellyfin_items) do
      add :id, :bigserial
    end

    # Step 2: Make id the primary key again
    execute "ALTER TABLE jellyfin_items DROP CONSTRAINT jellyfin_items_pkey"
    execute "ALTER TABLE jellyfin_items ADD PRIMARY KEY (id)"

    # Step 3: Drop the unique constraint on jellyfin_id since it's no longer the primary key
    execute "DROP INDEX IF EXISTS idx_unique_jellyfin_id"

    # Step 4: Remove the item_jellyfin_id from related tables or revert changes
    # For activities
    execute "DROP INDEX IF EXISTS idx_activities_item_jellyfin_id"

    # Step 5: Update schema references
    # These will be handled separately in schema files
  end
end
