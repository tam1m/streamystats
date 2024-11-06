defmodule StreamystatServer.Repo.Migrations.AddIndexNumberToItems do
  use Ecto.Migration

  def change do
    alter table(:jellyfin_items) do
      add(:index_number, :integer)
    end
  end
end
