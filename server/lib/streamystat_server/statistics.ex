defmodule StreamystatServer.Statistics do
  import Ecto.Query, warn: false
  alias StreamystatServer.Jellyfin.PlaybackSession
  alias StreamystatServer.Jellyfin.Item
  alias StreamystatServer.Jellyfin.Library
  alias StreamystatServer.Jellyfin.User
  alias StreamystatServer.Repo
  require Logger

  def create_playback_stat(attrs \\ %{}) do
    # This function is kept for backward compatibility
    # but delegates to create_playback_session
    StreamystatServer.Contexts.PlaybackSessions.create_playback_session(attrs)
  end

  def get_formatted_stats(start_date, end_date, server_id, user_id \\ nil) do
    stats = get_stats(start_date, end_date, server_id, user_id)

    %{
      most_watched_items: get_top_watched_items(stats),
      watchtime_per_day: get_watchtime_per_day(stats),
      average_watchtime_per_week_day: get_average_watchtime_per_week_day(stats),
      total_watch_time: get_total_watch_time(stats)
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
        left_join: ps in PlaybackSession,
        on: ps.item_jellyfin_id == i.jellyfin_id and ps.server_id == i.server_id,
        where: i.server_id == ^server_id and i.type in ["Movie", "Episode"],
        group_by: [i.id, i.jellyfin_id, i.name, i.type],
        select: %{
          item_id: i.jellyfin_id,
          item: i,
          watch_count: coalesce(count(ps.id), 0),
          total_watch_time: coalesce(sum(ps.play_duration), 0)
        }
      )

    # Apply search filter if provided
    query =
      if search do
        search_term = "%#{search}%"

        where(
          base_query,
          [i, ps],
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
          order_by(query, [i, ps], asc: coalesce(count(ps.id), 0))

        {:watch_count, :desc} ->
          order_by(query, [i, ps], desc: coalesce(count(ps.id), 0))

        {:total_watch_time, :asc} ->
          order_by(query, [i, ps], asc: coalesce(sum(ps.play_duration), 0))

        {:total_watch_time, :desc} ->
          order_by(query, [i, ps], desc: coalesce(sum(ps.play_duration), 0))
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
    start_datetime = to_datetime(start_date)
    end_datetime = to_datetime(end_date, :end_of_day)

    query =
      from(ps in PlaybackSession,
        left_join: i in Item,
        on: ps.item_jellyfin_id == i.jellyfin_id and ps.server_id == i.server_id,
        where: ps.start_time >= ^start_datetime and ps.start_time <= ^end_datetime,
        order_by: [asc: ps.start_time],
        preload: [:user],
        select: %{
          date_created: ps.start_time,
          item_id: ps.item_jellyfin_id,
          item: i,
          user_id: ps.user_id,
          play_duration: ps.play_duration,
          playback_session: ps
        }
      )

    query = if server_id, do: query |> where([ps], ps.server_id == ^server_id), else: query
    query = if user_id, do: query |> where([ps], ps.user_jellyfin_id == ^user_id), else: query

    Repo.all(query)
  end

  defp to_datetime(date, time \\ :beginning_of_day) do
    time_struct = if time == :end_of_day, do: Time.new!(23, 59, 59), else: Time.new!(0, 0, 0)

    date
    |> DateTime.new!(time_struct, "Etc/UTC")
  end

  defp get_total_watch_time(stats) do
    stats
    |> Enum.reduce(0, fn stat, acc ->
      acc + (stat.play_duration || 0)
    end)
  end

  defp get_top_watched_items(stats) do
    stats
    |> Enum.group_by(fn
      %{item: %{type: type}} when not is_nil(type) -> type
      _ -> "Unknown"
    end)
    |> Enum.map(fn {item_type, type_stats} ->
      top_items =
        type_stats
        |> Enum.group_by(& &1.item_id)
        |> Enum.map(fn {item_id, items} ->
          total_play_count = length(items)
          total_play_duration = Enum.sum(Enum.map(items, & &1.play_duration))

          case Enum.at(items, 0).item do
            %Item{} = item ->
              %{
                id: item.id,
                name: item.name,
                type: item.type,
                production_year: item.production_year,
                series_name: item.series_name,
                season_name: item.season_name,
                index_number: item.index_number,
                jellyfin_id: item.jellyfin_id,
                total_play_count: total_play_count,
                total_play_duration: total_play_duration
              }

            _ ->
              # Handle case where item might be nil
              %{
                id: nil,
                name: "Unknown Item",
                type: item_type,
                production_year: nil,
                series_name: nil,
                season_name: nil,
                index_number: nil,
                jellyfin_id: item_id,
                total_play_count: total_play_count,
                total_play_duration: total_play_duration
              }
          end
        end)
        |> Enum.sort_by(& &1.total_play_duration, :desc)
        |> Enum.take(10)

      {item_type, top_items}
    end)
    |> Enum.into(%{})
  end

  defp get_watchtime_per_day([]), do: []

  defp get_watchtime_per_day(stats) do
    stats
    |> Enum.group_by(
      fn stat ->
        item_type = if stat.item, do: stat.item.type, else: "Unknown"
        {DateTime.to_date(stat.date_created), item_type}
      end,
      fn stat -> stat.play_duration || 0 end
    )
    |> Enum.map(fn {{date, item_type}, durations} ->
      %{
        date: Date.to_iso8601(date),
        item_type: item_type,
        total_duration: Enum.sum(durations)
      }
    end)
    |> Enum.group_by(& &1.date)
    |> Enum.map(fn {date, items} ->
      %{
        date: date,
        watchtime_by_type:
          Enum.map(items, fn item ->
            %{
              item_type: item.item_type,
              total_duration: item.total_duration
            }
          end)
      }
    end)
    |> Enum.sort_by(& &1.date)
  end

  defp get_average_watchtime_per_week_day(stats) do
    stats
    |> Enum.group_by(&Date.day_of_week(DateTime.to_date(&1.date_created)))
    |> Enum.map(fn {day_of_week, items} ->
      total_duration = Enum.sum(Enum.map(items, &(&1.play_duration || 0)))
      average_duration = if length(items) > 0, do: total_duration / length(items), else: 0

      %{
        day_of_week: day_of_week,
        average_duration: Float.round(average_duration, 2)
      }
    end)
    |> Enum.sort_by(& &1.day_of_week)
  end
end
