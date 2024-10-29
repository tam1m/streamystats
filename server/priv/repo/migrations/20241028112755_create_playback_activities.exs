defmodule StreamystatServer.Repo.Migrations.CreatePlaybackActivities do
  use Ecto.Migration

  def change do
    create table(:playback_activities) do
      add(:date_created, :naive_datetime, null: false)
      add(:server_id, references(:servers, on_delete: :delete_all), null: false)

      # Add other fields as needed. For example:
      add(:rowid, :integer)
      add(:item_id, :string)
      add(:user_id, :string)
      add(:client_name, :string)
      add(:device_name, :string)
      add(:device_id, :string)
      add(:play_method, :string)
      add(:play_duration, :integer)
      add(:play_count, :integer)

      timestamps()
    end

    # Add indexes as needed
    create(index(:playback_activities, [:server_id]))
    create(index(:playback_activities, [:date_created]))
    # You might want a unique constraint on rowid and server_id
    create(unique_index(:playback_activities, [:rowid, :server_id]))
  end
end
