defmodule StreamystatServerWeb.AuthController do
  use StreamystatServerWeb, :controller
  alias StreamystatServer.Servers
  alias StreamystatServer.Auth

  def login(conn, %{"server_id" => server_id, "username" => username, "password" => password}) do
    case Servers.get_server(server_id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> render(:error, message: "Server not found")

      server ->
        case Auth.authenticate_user(server, username, password) do
          {:ok, %{access_token: access_token, user: user}} ->
            conn
            |> put_status(:ok)
            |> render(:login, access_token: access_token, user: user)

          {:error, reason} ->
            conn
            |> put_status(:unauthorized)
            |> render(:error, message: reason)
        end
    end
  end
end
