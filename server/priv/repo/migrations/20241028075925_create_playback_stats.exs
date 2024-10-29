defmodule StreamystatServer.Repo.Migrations.CreatePlaybackStats do
  use Ecto.Migration

  def change do
    create table(:playback_stats) do
      add(:user_id, :string, null: false)
      add(:item_id, :string, null: false)
      add(:play_count, :integer, null: false)
      add(:total_duration, :integer, null: false)
      add(:date, :date, null: false)
      add(:server_id, references(:servers, on_delete: :delete_all), null: false)

      timestamps()
    end

    create(index(:playback_stats, [:server_id]))
    create(index(:playback_stats, [:date]))
  end
end
