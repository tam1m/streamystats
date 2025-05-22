defmodule StreamystatServer.Repo.Migrations.RemoveUserServerIdFromActivities do
  use Ecto.Migration

  def change do
    alter table(:activities) do
      remove :user_server_id
    end
  end
end
