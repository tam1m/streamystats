defmodule StreamystatServer.Repo.Migrations.AddLastSyncedPlaybackIdToServers do
  use Ecto.Migration

  def change do
    alter table(:servers) do
      add(:last_synced_playback_id, :integer, default: 0)
    end
  end
end
