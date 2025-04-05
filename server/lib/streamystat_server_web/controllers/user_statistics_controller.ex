defmodule StreamystatServerWeb.UserStatisticsController do
  use StreamystatServerWeb, :controller
  alias StreamystatServer.Statistics.Statistics
  alias StreamystatServer.Sessions.Models.PlaybackSession
  alias StreamystatServer.Repo
  import Ecto.Query
  require Logger

  def watchtime_per_day(conn, params) do
    end_date = params["end_date"] || Date.utc_today() |> Date.to_iso8601()

    start_date =
      params["start_date"] || Date.add(Date.from_iso8601!(end_date), -30) |> Date.to_iso8601()

    server_id = params["server_id"]
    current_user = conn.assigns.current_user

    with {:ok, start_date} <- Date.from_iso8601(start_date),
         {:ok, end_date} <- Date.from_iso8601(end_date) do
      watchtime_stats =
        if is_admin?(current_user) do
          Statistics.get_watchtime_per_day_stats(start_date, end_date, server_id)
        else
          Statistics.get_watchtime_per_day_stats(start_date, end_date, server_id, current_user["Id"])
        end

      render(conn, :watchtime_per_day, watchtime_stats: watchtime_stats)
    else
      {:error, _} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Invalid date format. Please use ISO 8601 (YYYY-MM-DD)."})
    end
  end

  def index(conn, params) do
    end_date = params["end_date"] || Date.utc_today() |> Date.to_iso8601()

    start_date =
      params["start_date"] || Date.add(Date.from_iso8601!(end_date), -30) |> Date.to_iso8601()

    server_id = params["server_id"]
    current_user = conn.assigns.current_user

    with {:ok, start_date} <- Date.from_iso8601(start_date),
         {:ok, end_date} <- Date.from_iso8601(end_date) do
      statistics =
        if is_admin?(current_user) do
          Statistics.get_formatted_stats(start_date, end_date, server_id)
        else
          Statistics.get_formatted_stats(start_date, end_date, server_id, current_user["Id"])
        end

      render(conn, :index, statistics: statistics)
    else
      {:error, _} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Invalid date format. Please use ISO 8601 (YYYY-MM-DD)."})
    end
  end

  def history(conn, params) do
    current_user = conn.assigns.current_user

    query =
      if is_admin?(current_user) do
        from(ps in PlaybackSession, order_by: [desc: ps.start_time], preload: [:user])
      else
        from(ps in PlaybackSession,
          where: ps.user_jellyfin_id == ^current_user["Id"],
          order_by: [desc: ps.start_time],
          preload: [:user]
        )
      end

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
        server_id -> paginated_query |> where([ps], ps.server_id == ^server_id)
      end

    watch_activity = Repo.all(paginated_query)

    render(conn, :history, watch_activity: watch_activity)
  end

  def items(conn, %{"server_id" => server_id} = params) do
    page =
      case Integer.parse(params["page"] || "1") do
        {page, _} when page > 0 -> page
        _ -> 1
      end

    search =
      case params["search"] do
        nil -> nil
        "" -> nil
        search -> String.trim(search)
      end

    sort_by =
      case params["sort_by"] do
        "watch_count" -> :watch_count
        "total_watch_time" -> :total_watch_time
        _ -> :total_watch_time
      end

    sort_order =
      case params["sort_order"] do
        "asc" -> :asc
        "desc" -> :desc
        _ -> :desc
      end

    # Handle content type filter
    content_type =
      case params["type"] do
        nil -> nil
        "" -> nil
        "Episode" -> "Episode"
        "Movie" -> "Movie"
        "Series" -> "Series"
        _ -> nil
      end

    Logger.debug(
      "Page: #{page}, Search: #{inspect(search)}, ID: #{inspect(server_id)}, " <>
      "Sort By: #{sort_by}, Sort Order: #{sort_order}, Type: #{inspect(content_type)}"
    )

    item_stats = Statistics.get_item_statistics(server_id, page, search, sort_by, sort_order, content_type)
    render(conn, :items, item_stats: item_stats)
  end

  def library_stats(conn, %{"server_id" => server_id}) do
    stats = Statistics.get_library_statistics(server_id)
    render(conn, :library_stats, stats: stats)
  end

  defp is_admin?(user) do
    user["Policy"]["IsAdministrator"] == true
  end
end
