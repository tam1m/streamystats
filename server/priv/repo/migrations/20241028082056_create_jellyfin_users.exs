defmodule StreamystatServer.Repo.Migrations.CreateJellyfinUsers do
  use Ecto.Migration

  def change do
    create table(:jellyfin_users) do
      add(:jellyfin_id, :string, null: false)
      add(:name, :string, null: false)
      add(:server_id, references(:servers, on_delete: :delete_all), null: false)

      timestamps()
    end

    create(unique_index(:jellyfin_users, [:jellyfin_id, :server_id]))
    create(index(:jellyfin_users, [:server_id]))
  end
end
