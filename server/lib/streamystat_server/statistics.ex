defmodule StreamystatServer.Statistics do
  import Ecto.Query, warn: false
  alias StreamystatServer.Jellyfin.PlaybackActivity
  alias StreamystatServer.Jellyfin.Item
  alias StreamystatServer.Jellyfin.Library
  alias StreamystatServer.Jellyfin.User
  alias StreamystatServer.Repo
  require Logger

  def create_playback_stat(attrs \\ %{}) do
    %PlaybackActivity{}
    |> PlaybackActivity.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, stat} ->
        {:ok, stat}

      {:error, changeset} ->
        Logger.warning("Failed to create playback stat: #{inspect(changeset.errors)}")
        {:error, changeset}
    end
  end

  def get_formatted_stats(start_date, end_date, server_id, user_id \\ nil) do
    stats = get_stats(start_date, end_date, server_id, user_id)

    %{
      most_watched_item: get_most_watched_item(stats),
      watchtime_per_day: get_watchtime_per_day(stats),
      average_watchtime_per_week_day: get_average_watchtime_per_week_day(stats)
    }
  end

  def get_library_statistics(server_id) do
    %{
      movies_count:
        Repo.one(
          from(i in Item, where: i.server_id == ^server_id and i.type == "Movie", select: count())
        ),
      episodes_count:
        Repo.one(
          from(i in Item,
            where: i.server_id == ^server_id and i.type == "Episode",
            select: count()
          )
        ),
      series_count:
        Repo.one(
          from(i in Item,
            where: i.server_id == ^server_id and i.type == "Series",
            select: count()
          )
        ),
      libraries_count:
        Repo.one(from(l in Library, where: l.server_id == ^server_id, select: count())),
      users_count: Repo.one(from(u in User, where: u.server_id == ^server_id, select: count()))
    }
  end

  def get_item_statistics(
        server_id,
        page \\ 1,
        search \\ nil,
        sort_by \\ :total_watch_time,
        sort_order \\ :desc
      ) do
    per_page = 20

    # Validate and normalize sort parameters
    sort_by =
      case sort_by do
        :watch_count -> :watch_count
        :total_watch_time -> :total_watch_time
        _ -> :total_watch_time
      end

    sort_order =
      case sort_order do
        :asc -> :asc
        :desc -> :desc
        _ -> :desc
      end

    # Base query for items of type "Movie" and "Episode"
    base_query =
      from(i in Item,
        left_join: pa in PlaybackActivity,
        on: pa.item_id == i.jellyfin_id and pa.server_id == i.server_id,
        where: i.server_id == ^server_id and i.type in ["Movie", "Episode"],
        group_by: [i.id, i.jellyfin_id, i.name, i.type],
        select: %{
          item_id: i.jellyfin_id,
          item: i,
          watch_count: coalesce(count(pa.id), 0),
          total_watch_time: coalesce(sum(pa.play_duration), 0)
        }
      )

    # Apply search filter if provided
    query =
      if search do
        search_term = "%#{search}%"

        where(
          base_query,
          [i, pa],
          ilike(i.name, ^search_term) or
            ilike(fragment("?::text", i.production_year), ^search_term) or
            ilike(i.season_name, ^search_term) or
            ilike(i.series_name, ^search_term)
        )
      else
        base_query
      end

    # Apply sorting
    query =
      case {sort_by, sort_order} do
        {:watch_count, :asc} ->
          order_by(query, [i, pa], asc: coalesce(count(pa.id), 0))

        {:watch_count, :desc} ->
          order_by(query, [i, pa], desc: coalesce(count(pa.id), 0))

        {:total_watch_time, :asc} ->
          order_by(query, [i, pa], asc: coalesce(sum(pa.play_duration), 0))

        {:total_watch_time, :desc} ->
          order_by(query, [i, pa], desc: coalesce(sum(pa.play_duration), 0))
      end

    # Paginate items
    offset = (page - 1) * per_page

    items =
      query
      |> limit(^per_page)
      |> offset(^offset)
      |> Repo.all()

    # Count total items
    total_items_query =
      from(i in Item,
        where: i.server_id == ^server_id and i.type in ["Movie", "Episode"],
        select: i.id
      )

    # Apply the same search filter to the count query
    total_items_query =
      if search do
        search_term = "%#{search}%"

        where(
          total_items_query,
          [i],
          ilike(i.name, ^search_term) or
            ilike(fragment("?::text", i.production_year), ^search_term) or
            ilike(i.season_name, ^search_term) or
            ilike(i.series_name, ^search_term)
        )
      else
        total_items_query
      end

    # Fetch total item count
    total_items = total_items_query |> Repo.aggregate(:count, :id)
    total_pages = div(total_items + per_page - 1, per_page)

    %{
      items: items,
      page: page,
      per_page: per_page,
      total_items: total_items,
      total_pages: total_pages,
      sort_by: sort_by,
      sort_order: sort_order
    }
  end

  defp get_stats(start_date, end_date, server_id, user_id) do
    start_datetime = to_naive_datetime(start_date)
    end_datetime = to_naive_datetime(end_date, :end_of_day)

    query =
      from(pa in PlaybackActivity,
        where: pa.date_created >= ^start_datetime and pa.date_created <= ^end_datetime,
        order_by: [asc: pa.date_created],
        preload: [:user]
      )

    query = if server_id, do: query |> where([pa], pa.server_id == ^server_id), else: query
    query = if user_id, do: query |> where([pa], pa.user_id == ^user_id), else: query

    Repo.all(query)
  end

  defp to_naive_datetime(date, time \\ :beginning_of_day) do
    date
    |> DateTime.new!(Time.new!(0, 0, 0), "Etc/UTC")
    |> DateTime.to_naive()
    |> then(fn
      naive_dt when time == :end_of_day -> NaiveDateTime.add(naive_dt, 86399, :second)
      naive_dt -> naive_dt
    end)
  end

  defp get_most_watched_item([]), do: nil

  defp get_most_watched_item(stats) do
    stats
    |> Enum.group_by(& &1.item_id)
    |> Enum.max_by(
      fn {_, items} ->
        Enum.sum(Enum.map(items, & &1.play_duration))
      end,
      fn -> {nil, []} end
    )
    |> then(fn {item_id, items} ->
      first_item = List.first(items)

      %{
        item_id: item_id,
        item_name: first_item.item_name,
        item_type: first_item.item_type,
        total_play_count: length(items),
        total_play_duration: Enum.sum(Enum.map(items, & &1.play_duration))
      }
    end)
  end

  defp get_watchtime_per_day([]), do: []

  defp get_watchtime_per_day(stats) do
    stats
    |> Enum.group_by(&NaiveDateTime.to_date(&1.date_created))
    |> Enum.map(fn {date, items} ->
      total_duration = Enum.sum(Enum.map(items, &(&1.play_duration || 0)))
      %{date: Date.to_iso8601(date), total_duration: total_duration}
    end)
    |> Enum.sort_by(& &1.date)
  end

  defp get_average_watchtime_per_week_day(stats) do
    stats
    |> Enum.group_by(&Date.day_of_week(NaiveDateTime.to_date(&1.date_created)))
    |> Enum.map(fn {day_of_week, items} ->
      total_duration = Enum.sum(Enum.map(items, &(&1.play_duration || 0)))
      average_duration = total_duration / length(items)

      %{
        day_of_week: day_of_week,
        average_duration: Float.round(average_duration, 2)
      }
    end)
    |> Enum.sort_by(& &1.day_of_week)
  end
end
