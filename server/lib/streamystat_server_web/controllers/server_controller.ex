defmodule StreamystatServerWeb.ServerController do
  use StreamystatServerWeb, :controller
  alias StreamystatServer.Servers

  def index(conn, _params) do
    servers = Servers.list_servers()
    render(conn, :index, servers: servers)
  end

  def create(conn, server_params) do
    case Servers.create_server(server_params) do
      {:ok, server} ->
        conn
        |> put_status(:created)
        |> render(:show, server: server)

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> put_view(json: StreamystatServerWeb.ChangesetJSON)
        |> render(:error, changeset: changeset)
    end
  end

  def show(conn, %{"id" => id}) do
    case Servers.get_server(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> put_view(StreamystatServerWeb.ErrorJSON)
        |> render("404.json", %{})

      server ->
        render(conn, :show, server: server)
    end
  end
end
