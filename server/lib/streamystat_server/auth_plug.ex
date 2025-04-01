defmodule StreamystatServerWeb.AuthPlug do
  import Plug.Conn
  alias StreamystatServer.Auth
  alias StreamystatServer.Servers.Servers
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
         {:ok, server} <- server_result,
         {:ok, user_id} <- Auth.verify_token(server, token),
         {:ok, user_info} <- Auth.get_user_info(server, user_id) do
      conn
      |> assign(:current_user_id, user_id)
      |> assign(:current_user, user_info)
      |> assign(:server, server)
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
