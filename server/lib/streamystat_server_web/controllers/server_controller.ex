defmodule StreamystatServerWeb.ServerController do
  use StreamystatServerWeb, :controller
  alias StreamystatServer.Servers.Servers
  alias StreamystatServer.BatchEmbedder
  alias StreamystatServer.Repo
  alias StreamystatServer.SessionAnalysis

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

  def embedding_progress(conn, %{"server_id" => server_id}) do
    # Get embedding progress for the server
    progress = BatchEmbedder.get_progress(String.to_integer(server_id))

    # Calculate percentage if available
    percentage = if progress.total > 0 do
      Float.round(progress.processed / progress.total * 100, 1)
    else
      0.0
    end

    # Add percentage to the progress data
    progress_with_percentage = Map.put(progress, :percentage, percentage)

    conn
    |> json(%{data: progress_with_percentage})
  end

  def clear_embeddings(conn, %{"id" => id}) do
    server = Repo.get(Server, id)

    case server do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Server not found"})

      _ ->
        case SessionAnalysis.remove_all_embeddings(server.id) do
          {:ok, count} ->
            json(conn, %{message: "Successfully cleared #{count} embeddings"})

          {:error, reason} ->
            conn
            |> put_status(:internal_server_error)
            |> json(%{error: reason})
        end
    end
  end
end
