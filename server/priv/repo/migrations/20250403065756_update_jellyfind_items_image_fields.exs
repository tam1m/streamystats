defmodule StreamystatServer.Repo.Migrations.UpdateJellyfindItemsImageFields do
  use Ecto.Migration

  def change do
    alter table(:jellyfin_items) do
      # Remove fields
      remove :series_primary_image_tag
      remove :series_studio

      # Add new field
      add :image_blur_hashes, :map
    end
  end
end
