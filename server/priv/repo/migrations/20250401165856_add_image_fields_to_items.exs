defmodule StreamystatServer.Repo.Migrations.AddImageFieldsToItems do
  use Ecto.Migration

  def change do
    alter table(:jellyfin_items) do
      add(:primary_image_tag, :text)
      add(:backdrop_image_tags, {:array, :text})
    end

    # Create an index to optimize queries that filter by image tags
    create index(:jellyfin_items, [:primary_image_tag])
  end
end
