defmodule StreamystatServer.Repo.Migrations.AddImageTagsToItems do
  use Ecto.Migration

  def change do
    alter table(:jellyfin_items) do
      add :primary_image_thumb_tag, :string
      add :primary_image_logo_tag, :string
    end
  end
end
