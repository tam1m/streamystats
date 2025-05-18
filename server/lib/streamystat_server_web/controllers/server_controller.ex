defmodule StreamystatServerWeb.ServerController do
  use StreamystatServerWeb, :controller
  alias StreamystatServer.Servers.Servers

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

  def update_settings(conn, %{"id" => id} = params) do
    settings_params = Map.drop(params, ["id"])
    openai_token_updated = Map.has_key?(settings_params, "open_ai_api_token")

    case Servers.get_server(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> put_view(StreamystatServerWeb.ErrorJSON)
        |> render("404.json", %{})

      server ->
        case Servers.update_server(server, settings_params) do
          {:ok, updated_server} ->
            # If OpenAI token was updated, start embedding process
            if openai_token_updated && updated_server.open_ai_api_token do
              # Start embedding process in a separate process
              Task.start(fn -> 
                StreamystatServer.BatchEmbedder.embed_items_for_server(
                  updated_server.id, 
                  updated_server.open_ai_api_token
                )
              end)
            end
            
            render(conn, :show, server: updated_server)

          {:error, changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> put_view(json: StreamystatServerWeb.ChangesetJSON)
            |> render(:error, changeset: changeset)
        end
    end
  end

  def delete(conn, %{"server_id" => id}) do
    case Servers.delete_server(id) do
      {:ok, _} ->
        send_resp(conn, :no_content, "")

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: reason})
    end
  end
end
