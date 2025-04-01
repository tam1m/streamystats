defmodule StreamystatServerWeb.StatisticsController do
  use StreamystatServerWeb, :controller
  alias StreamystatServer.Servers.Servers
  alias StreamystatServer.Statistics.Statistics
  require Logger

  def unwatched(conn, %{"server_id" => server_id} = params) do
    case Servers.get_server(server_id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> put_view(StreamystatServerWeb.ErrorJSON)
        |> render("404.json", %{})

      server ->
        page = params["page"] || "1"
        per_page = params["per_page"] || "20"
        type = params["type"] || "Movie"

        {page, _} = Integer.parse(page)
        {per_page, _} = Integer.parse(per_page)

        result = Statistics.get_unwatched_items(server.id, type, page, per_page)

        render(conn, :unwatched,
          items: result.items,
          page: result.page,
          per_page: result.per_page,
          total_items: result.total_items,
          total_pages: result.total_pages
        )
    end
  end
end
