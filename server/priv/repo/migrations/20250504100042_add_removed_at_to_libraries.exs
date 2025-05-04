defmodule StreamystatServer.Repo.Migrations.AddRemovedAtToLibraries do
  use Ecto.Migration

  def change do
    alter table(:jellyfin_libraries) do
      add(:removed_at, :utc_datetime)
    end
  end
end