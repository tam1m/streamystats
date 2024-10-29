defmodule StreamystatServer.Repo.Migrations.AddAdminIdToServers do
  use Ecto.Migration

  def change do
    alter table(:servers) do
      add(:admin_id, :string, null: false)
    end

    create(index(:servers, [:admin_id]))
  end
end
