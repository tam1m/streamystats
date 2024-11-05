defmodule StreamystatServer.Repo.Migrations.AlterItemStringColumns do
  use Ecto.Migration

  def change do
    alter table(:jellyfin_items) do
      modify(:name, :text)
      modify(:type, :text)
      modify(:original_title, :text)
      modify(:container, :text)
      modify(:sort_name, :text)
      modify(:path, :text)
      modify(:official_rating, :text)
      modify(:overview, :text)
      modify(:media_type, :text)
    end
  end
end
