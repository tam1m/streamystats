defmodule StreamystatServer.Repo.Migrations.AddSeriesFieldsToItems do
  use Ecto.Migration

  def change do
    alter table(:jellyfin_items) do
      add(:series_name, :text)
      add(:series_id, :text)
      add(:season_id, :text)
      add(:series_primary_image_tag, :text)
      add(:season_name, :text)
      add(:series_studio, :text)
    end
  end
end
