defmodule StreamystatServerWeb.AuthPlug do
  import Plug.Conn
  alias StreamystatServer.Auth
  alias StreamystatServer.Servers
  require Logger

  def init(opts), do: opts

  def call(conn, _opts) do
    auth_header = get_req_header(conn, "authorization")
    server_id = get_in(conn.path_params, ["server_id"])

    # Then try to get the server
    server_result =
      case Servers.get_server(server_id) do
        nil -> {:error, :not_found}
        server -> {:ok, server}
      end

    with ["Bearer " <> token] <- auth_header,
         true <- is_binary(server_id),
         {:ok, server} <- server_result do
      case Auth.verify_token(server, token) do
        {:ok, user_id} ->
          assign(conn, :current_user_id, user_id)

        error ->
          Logger.debug("Token verification failed: #{inspect(error)}")
          handle_unauthorized(conn)
      end
    else
      error ->
        Logger.debug("Authentication failed at step: #{inspect(error)}")
        handle_unauthorized(conn)
    end
  end

  defp handle_unauthorized(conn) do
    conn
    |> put_status(:unauthorized)
    |> Phoenix.Controller.put_view(json: StreamystatServerWeb.ErrorJSON)
    |> Phoenix.Controller.render(:error, message: "Invalid or missing token")
    |> halt()
  end
end
