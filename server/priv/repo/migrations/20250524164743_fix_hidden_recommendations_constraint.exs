defmodule StreamystatServer.Repo.Migrations.FixHiddenRecommendationsConstraint do
  use Ecto.Migration

  def up do
    # Drop the existing unique index if it exists
    drop_if_exists unique_index(:hidden_recommendations, [:user_jellyfin_id, :item_jellyfin_id, :server_id])

    # Create the unique index with the specific name that matches the constraint in the model
    create unique_index(:hidden_recommendations, [:user_jellyfin_id, :item_jellyfin_id, :server_id],
           name: "hidden_recommendations_user_jellyfin_id_item_jellyfin_id_server")
  end

  def down do
    # Drop the named unique index
    drop_if_exists index(:hidden_recommendations, [:user_jellyfin_id, :item_jellyfin_id, :server_id],
                        name: "hidden_recommendations_user_jellyfin_id_item_jellyfin_id_server")

    # Recreate the original unnamed unique index
    create unique_index(:hidden_recommendations, [:user_jellyfin_id, :item_jellyfin_id, :server_id])
  end
end
