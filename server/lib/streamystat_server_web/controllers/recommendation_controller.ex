defmodule StreamystatServerWeb.RecommendationController do
  use StreamystatServerWeb, :controller
  alias StreamystatServer.SessionAnalysis
  alias StreamystatServer.Repo
  alias StreamystatServer.Sessions.Models.PlaybackSession
  alias StreamystatServer.Jellyfin.Models.Item
  import Ecto.Query
  require Logger

  @doc """
  Returns recommendations based on user's viewing history
  """
  def for_me(conn, params) do
    try do
      user_id = get_user_id(conn)
      server_id = get_server_id(conn)
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
  Returns contextual recommendations based on current time/context
  """
  def contextual(conn, params) do
    try do
      user_id = get_user_id(conn)
      server_id = get_server_id(conn)
      limit = Map.get(params, "limit", "10") |> parse_limit()
      context = Map.get(params, "context", "auto") |> parse_context()

      recommendations = SessionAnalysis.find_contextual_recommendations(user_id,
        limit: limit,
        context: context,
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
  Returns genre-boosted recommendations
  """
  def genre_boosted(conn, params) do
    try do
      user_id = get_user_id(conn)
      server_id = get_server_id(conn)
      limit = Map.get(params, "limit", "10") |> parse_limit()
      genre = Map.get(params, "genre")

      recommendations = SessionAnalysis.find_similar_items_for_user(user_id,
        limit: limit,
        genre: genre,
        boost_user_genres: true,
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
  Returns items similar to a specific item
  """
  def similar_to(conn, %{"item_id" => item_jellyfin_id} = params) do
    try do
      user_id = get_user_id(conn)
      limit = Map.get(params, "limit", "10") |> parse_limit()

      # First check if the user has access to this item
      has_access = user_has_access_to_item?(user_id, item_jellyfin_id)

      if has_access do
        recommendations = SessionAnalysis.find_similar_items_to_item(item_jellyfin_id, limit)

        conn
        |> put_status(:ok)
        |> render(:recommendations, items: recommendations)
      else
        conn
        |> put_status(:forbidden)
        |> render(:error, error: "You don't have access to this item")
      end
    rescue
      e in RuntimeError ->
        conn
        |> put_status(:unauthorized)
        |> render(:error, error: e.message)
    end
  end

  @doc """
  Returns recommendations based on what the user is currently watching
  """
  def current_session(conn, %{"session_id" => session_id} = params) do
    try do
      user_id = get_user_id(conn)
      limit = Map.get(params, "limit", "10") |> parse_limit()

      # Check if this session belongs to the user
      session_id = parse_id(session_id)

      session_exists =
        Repo.exists?(
          from(s in PlaybackSession,
            where: s.id == ^session_id and s.user_jellyfin_id == ^user_id
          )
        )

      if session_exists do
        recommendations = SessionAnalysis.find_similar_items_for_session(session_id, limit)

        conn
        |> put_status(:ok)
        |> render(:recommendations, items: recommendations)
      else
        conn
        |> put_status(:forbidden)
        |> render(:error, error: "Session not found or doesn't belong to you")
      end
    rescue
      e in RuntimeError ->
        conn
        |> put_status(:unauthorized)
        |> render(:error, error: e.message)
    end
  end

  @doc """
  Returns "people who watched this also watched" recommendations
  """
  def others_watched(conn, %{"item_id" => item_jellyfin_id} = params) do
    try do
      user_id = get_user_id(conn)
      limit = Map.get(params, "limit", "10") |> parse_limit()

      # Check if the user has access to this item
      has_access = user_has_access_to_item?(user_id, item_jellyfin_id)

      if has_access do
        recommendations = SessionAnalysis.find_items_from_similar_sessions(item_jellyfin_id, limit)

        conn
        |> put_status(:ok)
        |> render(:recommendations, items: recommendations)
      else
        conn
        |> put_status(:forbidden)
        |> render(:error, error: "You don't have access to this item")
      end
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
  def hide_recommendation(conn, %{"item_id" => item_id}) do
    try do
      user_id = get_user_id(conn)
      server_id = get_server_id(conn)

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

  defp get_server_id(conn) do
    server_id = conn.assigns[:current_server_id]

    # Return nil if server_id is missing, will be handled in the endpoints
    if is_nil(server_id) do
      raise "Server not authenticated"
    else
      server_id
    end
  end

  defp parse_limit(limit_str) do
    case Integer.parse(limit_str) do
      {limit, _} when limit > 0 and limit <= 50 -> limit
      _ -> 10
    end
  end

  defp parse_context(context_str) do
    case context_str do
      "auto" -> :auto
      "weekend" -> :weekend
      "weekday" -> :weekday
      "evening" -> :evening
      "quick_watch" -> :quick_watch
      _ -> :auto
    end
  end

  defp parse_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {num, _} -> num
      # Use invalid ID if parsing fails
      _ -> -1
    end
  end

  defp parse_id(id) when is_integer(id), do: id
  defp parse_id(_), do: -1

  defp user_has_access_to_item?(user_id, item_jellyfin_id) do
    # Check if the user has ever watched this item
    has_watched =
      Repo.exists?(
        from(s in PlaybackSession,
          where: s.user_jellyfin_id == ^user_id and s.item_jellyfin_id == ^item_jellyfin_id
        )
      )

    if has_watched do
      true
    else
      # If the user hasn't watched it, check if the item is public and not removed
      # This logic would need to be customized based on your access control system
      # Here we're assuming all items are accessible if they exist and are not removed
      Repo.exists?(
        from(i in Item,
          where: i.jellyfin_id == ^item_jellyfin_id
            and is_nil(i.removed_at)  # Exclude removed items
        )
      )
    end
  end
end
