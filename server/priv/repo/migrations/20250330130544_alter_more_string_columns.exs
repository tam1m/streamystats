defmodule StreamystatServer.Repo.Migrations.AlterMoreStringColumns do
  use Ecto.Migration

  def change do
    # Add for libraries table if needed
    alter table(:jellyfin_libraries) do
      modify(:name, :text)
      modify(:type, :text)
    end

    # Add for activities table if needed
    alter table(:activities) do
      modify(:name, :text)
      modify(:short_overview, :text)
      modify(:type, :text)
    end
  end
end
