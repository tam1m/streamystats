# server/lib/streamystat_server/contexts/playback_sessions.ex
defmodule StreamystatServer.Contexts.PlaybackSessions do
  import Ecto.Query, warn: false
  alias StreamystatServer.Repo
  alias StreamystatServer.Sessions.Models.PlaybackSession
  alias StreamystatServer.Jellyfin.Models.User

  def list_playback_sessions(server, opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 20)
    user_id = Keyword.get(opts, :user_id)

    query =
      from(p in PlaybackSession,
        where: p.server_id == ^server.id
      )

    query =
      if user_id do
        from(p in query, where: p.user_id == ^user_id)
      else
        query
      end

    query
    |> order_by([p], desc: p.start_time)
    |> Repo.paginate(page: page, page_size: per_page)
  end

  def create_playback_session(attrs \\ %{}) do
    %PlaybackSession{}
    |> PlaybackSession.changeset(attrs)
    |> Repo.insert()
  end

  def get_user_by_jellyfin_id(jellyfin_id, server_id) do
    Repo.get_by(User, jellyfin_id: jellyfin_id, server_id: server_id)
  end

  def calculate_statistics(server_id, opts \\ []) do
    user_id = Keyword.get(opts, :user_id)

    # Base query
    query =
      from(p in PlaybackSession,
        where: p.server_id == ^server_id
      )

    # Add user filter if specified
    query =
      if user_id do
        from(p in query, where: p.user_id == ^user_id)
      else
        query
      end

    # Calculate total watch time
    total_watch_time_query =
      from(p in query,
        select: sum(p.play_duration)
      )

    total_watch_time = Repo.one(total_watch_time_query) || 0

    # Most watched items
    most_watched_items_query =
      from(p in query,
        group_by: [p.item_jellyfin_id, p.item_name, p.series_jellyfin_id, p.series_name],
        select: %{
          item_id: p.item_jellyfin_id,
          item_name: p.item_name,
          series_id: p.series_jellyfin_id,
          series_name: p.series_name,
          total_duration: sum(p.play_duration),
          play_count: count(p.id)
        },
        order_by: [desc: sum(p.play_duration)],
        limit: 10
      )

    most_watched_items = Repo.all(most_watched_items_query)

    # Calculate watchtime per day (last 30 days)
    thirty_days_ago = Date.add(Date.utc_today(), -30)

    watchtime_per_day_query =
      from(p in query,
        where: fragment("date(?)", p.start_time) >= ^thirty_days_ago,
        group_by: fragment("date(?)", p.start_time),
        select: %{
          date: fragment("date(?)", p.start_time),
          duration: sum(p.play_duration)
        },
        order_by: fragment("date(?)", p.start_time)
      )

    watchtime_per_day = Repo.all(watchtime_per_day_query)

    # Average watchtime per weekday
    avg_watchtime_per_weekday_query =
      from(p in query,
        group_by: fragment("EXTRACT(DOW FROM ?)", p.start_time),
        select: %{
          day_of_week: fragment("EXTRACT(DOW FROM ?)", p.start_time),
          avg_duration: avg(p.play_duration)
        },
        order_by: fragment("EXTRACT(DOW FROM ?)", p.start_time)
      )

    average_watchtime_per_week_day = Repo.all(avg_watchtime_per_weekday_query)

    # Return all statistics
    %{
      total_watch_time: total_watch_time,
      most_watched_items: most_watched_items,
      watchtime_per_day: watchtime_per_day,
      average_watchtime_per_week_day: average_watchtime_per_week_day
    }
  end
end
