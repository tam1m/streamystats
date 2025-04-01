defmodule StreamystatServerWeb.UserController do
  use StreamystatServerWeb, :controller
  alias StreamystatServer.Contexts.Users
  alias StreamystatServer.Auth
  alias StreamystatServer.Servers.Servers
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
         user_id when is_binary(user_id) <- conn.assigns[:current_user_id] do

      case Users.get_user(server, user_id) do
        {:ok, user_info} ->
          conn
          |> put_status(:ok)
          |> render(:me, user: user_info)

        {:error, :user_not_found} ->
          # User exists in Jellyfin but not in our system
          Logger.info("User #{user_id} not found in our system, checking Jellyfin directly")

          case Auth.get_user_info(server, user_id) do
            {:ok, jellyfin_user} ->
              Logger.info("Found user in Jellyfin, creating initial user record")

              # Create a temporary user record or minimal entry
              case Users.create_initial_user(server_id, jellyfin_user) do
                {:ok, _} ->
                  Logger.info("Successfully created initial user record for #{user_id}")

                  conn
                  |> put_status(:ok)
                  |> render(:me, user: jellyfin_user)

                {:error, error} ->
                  Logger.error("Failed to create initial user record: #{inspect(error)}")

                  conn
                  |> put_status(:internal_server_error)
                  |> put_view(json: StreamystatServerWeb.ErrorJSON)
                  |> render(:error, message: "Failed to create user record")
              end

            {:error, reason} ->
              Logger.error("Failed to fetch user from Jellyfin: #{inspect(reason)}")

              conn
              |> put_status(:unauthorized)
              |> put_view(json: StreamystatServerWeb.ErrorJSON)
              |> render(:error, message: "User not found in Jellyfin")
          end

        {:error, reason} ->
          Logger.error("Error retrieving user info: #{inspect(reason)}")

          conn
          |> put_status(:unauthorized)
          |> put_view(json: StreamystatServerWeb.ErrorJSON)
          |> render(:error, message: reason)
      end
    else
      nil ->
        Logger.error("Server with ID #{server_id} not found")

        conn
        |> put_status(:not_found)
        |> put_view(json: StreamystatServerWeb.ErrorJSON)
        |> render(:error, message: "Server not found")

      {:error, reason} ->
        Logger.error("Error in me function: #{inspect(reason)}")

        conn
        |> put_status(:unauthorized)
        |> put_view(json: StreamystatServerWeb.ErrorJSON)
        |> render(:error, message: reason)
    end
  end
end
