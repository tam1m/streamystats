defmodule StreamystatServer.Repo.Migrations.AddPlaybackTrackingFields do
  use Ecto.Migration

  def change do
    alter table(:playback_sessions) do
      add(:position_ticks, :bigint)
      add(:runtime_ticks, :bigint)
      add(:percent_complete, :float)
      add(:completed, :boolean, default: false)
    end
  end
end
