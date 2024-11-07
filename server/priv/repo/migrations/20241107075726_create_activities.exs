# Create a new migration file
defmodule StreamystatServer.Repo.Migrations.CreateActivities do
  use Ecto.Migration

  def change do
    create table(:activities) do
      add :jellyfin_id, :integer, null: false
      add :name, :string
      add :short_overview, :text
      add :type, :string
      add :date, :utc_datetime
      add :user_id, references(:jellyfin_users, on_delete: :nilify_all)
      add :server_id, references(:servers, on_delete: :delete_all)
      add :severity, :string

      timestamps()
    end

    create index(:activities, [:jellyfin_id, :server_id], unique: true)
    create index(:activities, [:user_id])
    create index(:activities, [:server_id])
    create index(:activities, [:date])
  end
end
