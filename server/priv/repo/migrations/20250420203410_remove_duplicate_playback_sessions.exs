defmodule StreamystatServer.Repo.Migrations.RemoveDuplicatePlaybackSessions do
  use Ecto.Migration

  def change do
    # Create a temporary function to find duplicates and keep only the latest version
    execute """
    CREATE OR REPLACE FUNCTION deduplicate_playback_sessions() RETURNS void AS $$
    DECLARE
      duplicate_record RECORD;
    BEGIN
      FOR duplicate_record IN (
        SELECT
          item_jellyfin_id,
          user_jellyfin_id,
          start_time,
          server_id,
          COUNT(*) as count,
          array_agg(id ORDER BY updated_at DESC) as ids
        FROM
          playback_sessions
        GROUP BY
          item_jellyfin_id, user_jellyfin_id, start_time, server_id
        HAVING
          COUNT(*) > 1
      ) LOOP
        -- Keep the first ID (most recently updated) and delete the rest
        DELETE FROM playback_sessions
        WHERE id = ANY(duplicate_record.ids[2:array_length(duplicate_record.ids, 1)]);
      END LOOP;
    END;
    $$ LANGUAGE plpgsql;
    """

    # Execute the function to deduplicate records
    execute "SELECT deduplicate_playback_sessions();"

    # Clean up - drop the temporary function
    execute "DROP FUNCTION deduplicate_playback_sessions();"
  end
end
