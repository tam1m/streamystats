defmodule StreamystatServer.Repo.Migrations.AddFieldsToJellyfinItems do
  use Ecto.Migration

  def change do
    alter table(:jellyfin_items) do
      add(:original_title, :string)
      add(:etag, :string)
      add(:date_created, :utc_datetime)
      add(:container, :string)
      add(:sort_name, :string)
      add(:premiere_date, :utc_datetime)
      add(:external_urls, {:array, :map})
      add(:path, :string)
      add(:official_rating, :string)
      add(:overview, :text)
      add(:genres, {:array, :string})
      add(:community_rating, :float)
      add(:runtime_ticks, :bigint)
      add(:production_year, :integer)
      add(:is_folder, :boolean)
      add(:parent_id, :string)
      add(:media_type, :string)
      add(:width, :integer)
      add(:height, :integer)
    end
  end
end
