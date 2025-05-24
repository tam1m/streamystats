defmodule StreamystatServerWeb.RecommendationController do
  use StreamystatServerWeb, :controller
  alias StreamystatServer.SessionAnalysis
  require Logger

  @doc """
  Returns simple recommendations based on user's recently watched content
  """
  def for_me(conn, params) do
    try do
      user_id = get_user_id(conn)
      server_id = params["server_id"]
      Logger.info("Getting recommendations for user #{user_id} on server #{server_id}")
      limit = Map.get(params, "limit", "10") |> parse_limit()

      recommendations = SessionAnalysis.find_similar_items_for_user(user_id,
        limit: limit,
        server_id: server_id
      )

      conn
      |> put_status(:ok)
      |> render(:recommendations, items: recommendations)
    rescue
      e in RuntimeError ->
        conn
        |> put_status(:unauthorized)
        |> render(:error, error: e.message)
    end
  end

  @doc """
  Hides a recommendation for the current user
  """
  def hide_recommendation(conn, %{"item_id" => item_id, "server_id" => server_id}) do
    try do
      user_id = get_user_id(conn)

      case SessionAnalysis.hide_recommendation(user_id, item_id, server_id) do
        {:ok, _hidden_rec} ->
          conn
          |> put_status(:ok)
          |> json(%{success: true, message: "Recommendation hidden successfully"})

        {:error, changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{success: false, error: "Failed to hide recommendation", details: changeset})
      end
    rescue
      e in RuntimeError ->
        conn
        |> put_status(:unauthorized)
        |> render(:error, error: e.message)
    end
  end

  # Private helper functions

  defp get_user_id(conn) do
    user_id = conn.assigns[:current_user_id]

    # Return nil if user_id is missing, will be handled in the endpoints
    if is_nil(user_id) do
      raise "User not authenticated"
    else
      user_id
    end
  end

  defp parse_limit(limit_str) do
    case Integer.parse(limit_str) do
      {limit, _} when limit > 0 and limit <= 50 -> limit
      _ -> 10
    end
  end
end
