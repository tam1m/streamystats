defmodule StreamystatServer.Recommendations.Models.HiddenRecommendation do
  use Ecto.Schema
  import Ecto.Changeset

  schema "hidden_recommendations" do
    field :user_jellyfin_id, :string
    field :item_jellyfin_id, :string
    field :hidden_at, :utc_datetime

    belongs_to :server, StreamystatServer.Servers.Models.Server

    timestamps()
  end

  @doc false
  def changeset(hidden_recommendation, attrs) do
    hidden_recommendation
    |> cast(attrs, [:user_jellyfin_id, :item_jellyfin_id, :server_id, :hidden_at])
    |> validate_required([:user_jellyfin_id, :item_jellyfin_id, :server_id])
    |> unique_constraint([:user_jellyfin_id, :item_jellyfin_id, :server_id],
         name: "hidden_recommendations_user_jellyfin_id_item_jellyfin_id_server")
  end
end
