defmodule StreamystatServer.Repo.Migrations.RemoveAdminIdFromServers do
  use Ecto.Migration

  def change do
    alter table(:servers) do
      remove(:admin_id)
    end
  end
end
