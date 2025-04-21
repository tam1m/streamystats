defmodule StreamystatServer.Repo.Migrations.AddUniqueIndexToPlaybackSessions do
  use Ecto.Migration

  def change do
    # Create a unique index to prevent duplicate playback sessions
    create unique_index(:playback_sessions, [:item_jellyfin_id, :user_jellyfin_id, :start_time, :server_id],
      name: :playback_sessions_unique_index)
  end
end
