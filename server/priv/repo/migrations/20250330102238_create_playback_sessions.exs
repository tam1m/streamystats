defmodule StreamystatServer.Repo.Migrations.CreatePlaybackSessions do
  use Ecto.Migration

  def change do
    create table(:playback_sessions) do
      add(:user_jellyfin_id, :string, null: false)
      add(:device_id, :string)
      add(:device_name, :string)
      add(:client_name, :string)
      add(:item_jellyfin_id, :string, null: false)
      add(:item_name, :string)
      add(:series_jellyfin_id, :string)
      add(:series_name, :string)
      add(:season_jellyfin_id, :string)
      add(:play_duration, :integer, null: false)
      add(:play_method, :string)
      add(:start_time, :utc_datetime, null: false)
      add(:end_time, :utc_datetime)

      add(:user_id, references(:jellyfin_users, on_delete: :nilify_all))
      add(:server_id, references(:servers, on_delete: :delete_all), null: false)

      timestamps()
    end

    create(index(:playback_sessions, [:server_id]))
    create(index(:playback_sessions, [:user_id]))
    create(index(:playback_sessions, [:start_time]))
    create(index(:playback_sessions, [:item_jellyfin_id]))
  end
end
