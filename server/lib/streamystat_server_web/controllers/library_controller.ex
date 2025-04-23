defmodule StreamystatServerWeb.LibraryController do
  use StreamystatServerWeb, :controller
  alias StreamystatServer.Jellyfin.Libraries
  require Logger

  def index(conn, %{"server_id" => server_id}) do
    libraries = Libraries.get_libraries(server_id)
    render(conn, :index, libraries: libraries)
  end

  def show(conn, %{"server_id" => server_id, "id" => library_id}) do
    case Libraries.get_library(server_id, library_id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> put_view(StreamystatServerWeb.ErrorJSON)
        |> render(:"404")

      library ->
        render(conn, :show, library: library)
    end
  end
end
