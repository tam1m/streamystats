defmodule StreamystatServer.Repo.Migrations.ChangeActivitiesPrimaryKeyToJellyfinId do
  use Ecto.Migration

  def up do
    # First create a unique index on jellyfin_id to ensure it can be a primary key
    execute "CREATE UNIQUE INDEX IF NOT EXISTS idx_activities_jellyfin_id_server_id ON activities (jellyfin_id, server_id)"

    # Drop the primary key constraint
    execute "ALTER TABLE activities DROP CONSTRAINT activities_pkey"

    # Add a primary key constraint based on jellyfin_id
    # Note: We're keeping server_id as part of the composite primary key since activities
    # are scoped to servers (and jellyfin_id is unique within a server)
    execute "ALTER TABLE activities ADD PRIMARY KEY (jellyfin_id, server_id)"

    # Drop the auto-generated ID column as it's no longer needed
    execute "ALTER TABLE activities DROP COLUMN IF EXISTS id"
  end

  def down do
    # To undo this migration, we need to:
    # 1. Add back the id column
    # 2. Populate it with unique values
    # 3. Set it as the primary key

    execute "ALTER TABLE activities DROP CONSTRAINT activities_pkey"

    # Add back the id column
    execute "ALTER TABLE activities ADD COLUMN id SERIAL"

    # Set it as the primary key
    execute "ALTER TABLE activities ADD PRIMARY KEY (id)"

    # Keep the unique index on jellyfin_id and server_id
    execute "CREATE UNIQUE INDEX IF NOT EXISTS idx_activities_jellyfin_id_server_id ON activities (jellyfin_id, server_id)"
  end
end
