defmodule StreamystatServer.Repo.Migrations.CreateServers do
  use Ecto.Migration

  def change do
    create table(:servers) do
      add(:name, :string, null: false)
      add(:url, :string, null: false)
      add(:api_key, :string, null: false)

      timestamps()
    end

    create(unique_index(:servers, [:name]))
  end
end
