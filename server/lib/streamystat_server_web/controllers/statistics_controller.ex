defmodule StreamystatServerWeb.StatisticsController do
  use StreamystatServerWeb, :controller
  alias StreamystatServer.Statistics
  alias StreamystatServer.Jellyfin.PlaybackActivity
  alias StreamystatServer.Repo
  import Ecto.Query

  def index(conn, params) do
    end_date = params["end_date"] || Date.utc_today() |> Date.to_iso8601()

    start_date =
      params["start_date"] || Date.add(Date.from_iso8601!(end_date), -30) |> Date.to_iso8601()

    server_id = params["server_id"]

    with {:ok, start_date} <- Date.from_iso8601(start_date),
         {:ok, end_date} <- Date.from_iso8601(end_date) do
      statistics = Statistics.get_formatted_stats(start_date, end_date, server_id)
      render(conn, :index, statistics: statistics)
    else
      {:error, _} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Invalid date format. Please use ISO 8601 (YYYY-MM-DD)."})
    end
  end

  @spec history(Plug.Conn.t(), nil | maybe_improper_list() | map()) :: Plug.Conn.t()
  def history(conn, params) do
    query =
      from(pa in PlaybackActivity,
        order_by: [desc: pa.date_created],
        preload: [:user]
      )

    # Add pagination
    page = params["page"] || "1"
    per_page = params["per_page"] || "20"

    {page, _} = Integer.parse(page)
    {per_page, _} = Integer.parse(per_page)

    paginated_query =
      query
      |> limit(^per_page)
      |> offset((^page - 1) * ^per_page)

    # Add server_id filter if provided
    paginated_query =
      case params["server_id"] do
        nil -> paginated_query
        server_id -> paginated_query |> where([pa], pa.server_id == ^server_id)
      end

    watch_activity = Repo.all(paginated_query)

    render(conn, :history, watch_activity: watch_activity)
  end
end
