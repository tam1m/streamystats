defmodule StreamystatServer.Repo.Migrations.CleanupAfterJellyfinIdMigration do
  use Ecto.Migration

  def up do
    # This migration will run after all the other jellyfin_id migrations have completed

    # Remove legacy item_id field from activities
    alter table(:activities) do
      remove_if_exists :item_id, :string
    end

    # Update any views, triggers, or other database objects that may reference the old id column
    # None identified in the current code

    # Optional: Add check constraints to ensure data consistency
    execute "ALTER TABLE jellyfin_items ADD CONSTRAINT check_jellyfin_id_not_null CHECK (jellyfin_id IS NOT NULL)"
  end

  def down do
    # Add back the legacy item_id field to activities
    alter table(:activities) do
      add_if_not_exists :item_id, :string
    end

    # Remove any constraints added in the up migration
    execute "ALTER TABLE jellyfin_items DROP CONSTRAINT IF EXISTS check_jellyfin_id_not_null"
  end
end
