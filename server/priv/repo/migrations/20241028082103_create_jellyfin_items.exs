defmodule StreamystatServer.Repo.Migrations.CreateJellyfinItems do
  use Ecto.Migration

  def change do
    create table(:jellyfin_items) do
      add(:jellyfin_id, :string, null: false)
      add(:name, :string, null: false)
      add(:type, :string, null: false)
      add(:library_id, references(:jellyfin_libraries, on_delete: :delete_all), null: false)
      add(:server_id, references(:servers, on_delete: :delete_all), null: false)
      timestamps()
    end

    create(unique_index(:jellyfin_items, [:jellyfin_id, :library_id]))
    create(unique_index(:jellyfin_items, [:jellyfin_id, :server_id]))

    create(index(:jellyfin_items, [:library_id]))
    create(index(:jellyfin_items, [:server_id]))
  end
end
