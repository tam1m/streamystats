defmodule StreamystatServer.Repo.Migrations.UpdateLastActivityDateToUtcDatetime do
  use Ecto.Migration

  def change do
    alter table(:jellyfin_users) do
      modify(:last_activity_date, :utc_datetime)
    end
  end
end
