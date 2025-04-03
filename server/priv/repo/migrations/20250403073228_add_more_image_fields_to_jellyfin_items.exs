defmodule StreamystatServer.Repo.Migrations.AddMoreImageFieldsToJellyfinItems do
  use Ecto.Migration

  def change do
    alter table(:jellyfin_items) do
      add :parent_index_number, :integer
      add :video_type, :string
      add :has_subtitles, :boolean
      add :channel_id, :string
      add :parent_backdrop_item_id, :string
      add :parent_backdrop_image_tags, {:array, :string}
      add :parent_thumb_item_id, :string
      add :parent_thumb_image_tag, :string
      add :location_type, :string
      add :primary_image_aspect_ratio, :float
      add :series_primary_image_tag, :string
    end
  end
end
