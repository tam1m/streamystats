defmodule StreamystatServer.Repo.Migrations.AddItemTypeAndNameToPlaybackActivities do
  use Ecto.Migration

  def change do
    alter table(:playback_activities) do
      add(:item_type, :string)
      add(:item_name, :string)
    end
  end
end
