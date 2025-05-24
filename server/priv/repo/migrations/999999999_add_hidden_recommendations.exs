defmodule StreamystatServer.Repo.Migrations.AddHiddenRecommendations do
  use Ecto.Migration

  def change do
    create table(:hidden_recommendations) do
      add :user_jellyfin_id, :string, null: false
      add :item_jellyfin_id, :string, null: false
      add :server_id, references(:servers, on_delete: :delete_all), null: false
      add :hidden_at, :utc_datetime, null: false, default: fragment("now()")

      timestamps()
    end

    create index(:hidden_recommendations, [:user_jellyfin_id, :server_id])
    create index(:hidden_recommendations, [:item_jellyfin_id, :server_id])
    create unique_index(:hidden_recommendations, [:user_jellyfin_id, :item_jellyfin_id, :server_id])
  end
end
