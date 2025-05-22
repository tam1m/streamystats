defmodule StreamystatServer.Repo.Migrations.FixActivitiesItemIdColumn do
  use Ecto.Migration

  def up do
    # Check if the item_id column exists using a DO block
    execute """
    DO $$
    BEGIN
      IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_name = 'activities' AND column_name = 'item_id'
      ) THEN
        ALTER TABLE activities DROP COLUMN item_id;
      END IF;
    END $$;
    """

    # Check if item_jellyfin_id column exists, and add it if not
    execute """
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_name = 'activities' AND column_name = 'item_jellyfin_id'
      ) THEN
        ALTER TABLE activities ADD COLUMN item_jellyfin_id text;
      END IF;
    END $$;
    """
  end

  def down do
    # Add back the item_id column if needed
    execute """
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_name = 'activities' AND column_name = 'item_id'
      ) THEN
        ALTER TABLE activities ADD COLUMN item_id text;
      END IF;
    END $$;
    """
  end
end
