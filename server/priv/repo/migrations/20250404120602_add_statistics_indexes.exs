defmodule StreamystatServer.Repo.Migrations.AddStatisticsIndexes do
  use Ecto.Migration

 def change do
    # Indexes for PlaybackSession table
    create_if_not_exists index(:playback_sessions, [:start_time])
    create_if_not_exists index(:playback_sessions, [:server_id])
    create_if_not_exists index(:playback_sessions, [:user_jellyfin_id])
    create_if_not_exists index(:playback_sessions, [:item_jellyfin_id])
    create_if_not_exists index(:playback_sessions, [:server_id, :start_time])
    create_if_not_exists index(:playback_sessions, [:server_id, :user_jellyfin_id])

    # Compound indexes for common query patterns
    create_if_not_exists index(:playback_sessions, [:server_id, :user_jellyfin_id, :start_time])
    create_if_not_exists index(:playback_sessions, [:server_id, :item_jellyfin_id])

    # Indexes for Item table
    create_if_not_exists index(:jellyfin_items, [:server_id])
    create_if_not_exists index(:jellyfin_items, [:jellyfin_id])
    create_if_not_exists index(:jellyfin_items, [:type])
    create_if_not_exists index(:jellyfin_items, [:server_id, :jellyfin_id])
    create_if_not_exists index(:jellyfin_items, [:server_id, :type])

    # Index for efficient joining
    create_if_not_exists index(:playback_sessions, [:server_id, :item_jellyfin_id, :start_time])

    # Index for efficient sorting of watch time
    create_if_not_exists index(:playback_sessions, [:play_duration])
  end
end
