defmodule StreamystatServerWeb.UserController do
  use StreamystatServerWeb, :controller
  alias StreamystatServer.Contexts.Users
  alias StreamystatServer.Auth
  alias StreamystatServer.Servers
  require Logger

  def index(conn, %{"server_id" => server_id}) do
    users = Users.get_users(server_id)

    users_with_details =
      Enum.map(users, fn user ->
        watch_stats = Users.get_user_watch_stats(server_id, user.id)
        Logger.debug("User ID: #{user.id}, Watch Stats: #{inspect(watch_stats)}")
        %{user: user, watch_stats: watch_stats}
      end)

    render(conn, :index, users: users_with_details)
  end

  def show(conn, %{"server_id" => server_id, "id" => user_id}) do
    case Users.get_user(server_id, user_id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> put_view(StreamystatServerWeb.ErrorJSON)
        |> render(:"404")

      user ->
        watch_history = Users.get_user_watch_history(server_id, user.id)
        watch_stats = Users.get_user_watch_stats(server_id, user.id)
        watch_time_per_day = Users.get_user_watch_time_per_day(server_id, user.id)
        genre_stats = Users.get_user_genre_watch_time(server_id, user.id)
        longest_streak = Users.get_user_longest_streak(user.id)

        render(conn, :show,
          user: user,
          watch_history: watch_history,
          watch_stats: watch_stats,
          watch_time_per_day: watch_time_per_day,
          genre_stats: genre_stats,
          longest_streak: longest_streak
        )
    end
  end

  def me(conn, %{"server_id" => server_id}) do
    with {:ok, server} <- Servers.get_server(server_id),
         user_id when is_binary(user_id) <- conn.assigns[:current_user_id],
         {:ok, user_info} <- Auth.get_user_info(server, user_id) do
      conn
      |> put_status(:ok)
      |> render(:me, user: user_info)
    else
      nil ->
        conn
        |> put_status(:not_found)
        |> put_view(json: StreamystatServerWeb.ErrorJSON)
        |> render(:error, message: "Server not found")

      {:error, reason} ->
        conn
        |> put_status(:unauthorized)
        |> put_view(json: StreamystatServerWeb.ErrorJSON)
        |> render(:error, message: reason)
    end
  end
end
