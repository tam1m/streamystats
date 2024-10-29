defmodule StreamystatServer.Repo.Migrations.CreateJellyfinLibraries do
  use Ecto.Migration

  def change do
    create table(:jellyfin_libraries) do
      add(:jellyfin_id, :string, null: false)
      add(:name, :string, null: false)
      add(:type, :string, null: false)
      add(:server_id, references(:servers, on_delete: :delete_all), null: false)

      timestamps()
    end

    create(unique_index(:jellyfin_libraries, [:jellyfin_id, :server_id]))
    create(index(:jellyfin_libraries, [:server_id]))
  end
end
