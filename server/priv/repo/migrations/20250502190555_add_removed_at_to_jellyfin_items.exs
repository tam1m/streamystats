defmodule StreamystatServer.Repo.Migrations.AddRemovedAtToJellyfinItems do
  use Ecto.Migration

  def change do
    alter table(:jellyfin_items) do
      add :removed_at, :utc_datetime
    end

    create index(:jellyfin_items, [:removed_at])
  end
end