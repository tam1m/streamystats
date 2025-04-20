defmodule StreamystatServer.Statistics.Statistics do
  import Ecto.Query, warn: false
  alias StreamystatServer.Sessions.Models.PlaybackSession
  alias StreamystatServer.Jellyfin.Models.Item
  alias StreamystatServer.Jellyfin.Models.Library
  alias StreamystatServer.Jellyfin.Models.User
  alias StreamystatServer.Repo
  require Logger

  def create_playback_stat(attrs \\ %{}) do
    StreamystatServer.Contexts.PlaybackSessions.create_playback_session(attrs)
  end


  def get_watchtime_per_day_stats(start_date, end_date, server_id, user_id \\ nil) do

    start_datetime = to_datetime(start_date)
    end_datetime = to_datetime(end_date, :end_of_day)


    query =
      from ps in PlaybackSession,
        left_join: i in Item,
        on: ps.item_jellyfin_id == i.jellyfin_id and ps.server_id == i.server_id,
        where: ps.start_time >= ^start_datetime and ps.start_time <= ^end_datetime,
      where: ps.server_id == ^server_id


    query = if user_id, do: query |> where([ps], ps.user_jellyfin_id == ^user_id), else: query


    watchtime_data =
        query
      |> group_by([ps, i], [fragment("date_trunc('day', ?)", ps.start_time), i.type])
      |> select([ps, i], %{
        date: fragment("date_trunc('day', ?)", ps.start_time),
        item_type: coalesce(i.type, "Unknown"),
        total_duration: sum(ps.play_duration)
      })
      |> Repo.all()


    formatted_data =
      watchtime_data
      |> Enum.group_by(&Date.to_iso8601(&1.date))
    |> Enum.map(fn {date, items} ->
      %{
        date: date,
          watchtime_by_type: Enum.map(items, fn item ->
            %{
              item_type: item.item_type,
              total_duration: item.total_duration || 0
            }
          end)
      }
    end)
    |> Enum.sort_by(& &1.date)

    %{watchtime_per_day: formatted_data}
  end

  def get_formatted_stats(_start_date, _end_date, server_id, user_id \\ nil) do
    total_watch_time = get_total_watch_time_db(server_id, user_id)
    most_watched_date = get_most_watched_date_db(server_id, user_id)
    most_watched_items = get_top_watched_items_db(server_id, user_id)
    average_watchtime_per_week_day = get_average_watchtime_per_week_day_db(server_id, user_id)
    watchtime_per_week_day = get_watchtime_per_week_day_db(server_id, user_id)
    watchtime_per_hour = get_watchtime_per_hour_db(server_id, user_id)
      %{
      most_watched_items: most_watched_items,
      average_watchtime_per_week_day: average_watchtime_per_week_day,
      total_watch_time: total_watch_time,
      most_watched_date: most_watched_date,
      watchtime_per_week_day: watchtime_per_week_day,
      watchtime_per_hour: watchtime_per_hour
      }
  end

  def get_unwatched_items(server_id, type \\ "Movie", page \\ 1, per_page \\ 20) do
    type = if type in ["Movie", "Series", "Episode"], do: type, else: "Movie"

    watched_items_query =
      from ps in PlaybackSession,
      where: ps.server_id == ^server_id,
      select: ps.item_jellyfin_id

    query =
      from i in Item,
      where: i.server_id == ^server_id and i.type == ^type,
      where: not(i.jellyfin_id in subquery(watched_items_query)),
      order_by: [desc: i.date_created],
      select: i

    offset = (page - 1) * per_page

    items =
      query
      |> limit(^per_page)
      |> offset(^offset)
      |> Repo.all()

    total_items =
      from(i in Item,
        where: i.server_id == ^server_id and i.type == ^type,
        where: not(i.jellyfin_id in subquery(watched_items_query)),
        select: count(i.id)
      )
      |> Repo.one()

    total_pages = div(total_items + per_page - 1, per_page)

    %{
      items: items,
      page: page,
      per_page: per_page,
      total_items: total_items,
      total_pages: total_pages
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

  def get_item_details_statistics(server_id, item_id, user_id \\ nil) do
    # First check if the item exists
    item =
      from(i in Item,
        where: i.server_id == ^server_id and i.jellyfin_id == ^item_id,
        select: i
      )
      |> Repo.one()

    if is_nil(item) do
      nil
    else
      # This will hold our base query depending on the item type
      base_playback_query = cond do
        # For series, we need to find all episodes that belong to this series
        item.type == "Series" ->
          from(ps in PlaybackSession,
            join: i in Item, on: ps.item_jellyfin_id == i.jellyfin_id and ps.server_id == i.server_id,
            where: ps.server_id == ^server_id and i.series_id == ^item_id)

        # For seasons, we need to find all episodes that belong to this season
        item.type == "Season" ->
          from(ps in PlaybackSession,
            join: i in Item, on: ps.season_jellyfin_id == i.jellyfin_id and ps.server_id == i.server_id,
            where: ps.server_id == ^server_id and i.jellyfin_id == ^item_id)

        # For regular items we can directly query using the item_id
        true ->
          from(ps in PlaybackSession,
            where: ps.server_id == ^server_id and ps.item_jellyfin_id == ^item_id)
      end

      # Apply user filter if provided (for non-admin users)
      base_playback_query =
        if user_id do
          base_playback_query |> where([ps], ps.user_jellyfin_id == ^user_id)
        else
          base_playback_query
        end

      # Total views and watch time
      total_stats =
        from(ps in subquery(base_playback_query),
          select: %{
            total_views: count(ps.id),
            total_watch_time: sum(ps.play_duration)
          })
        |> Repo.one()

      # Completion rate (percentage of views that completed at least 90%)
      completion_query =
        from(ps in subquery(base_playback_query),
          select: %{
            completed_views: fragment("COUNT(CASE WHEN percent_complete >= 90 THEN 1 END)"),
            total_views: count(ps.id)
          })
        |> Repo.one()

      completion_rate =
        if completion_query.total_views > 0 do
          (completion_query.completed_views / completion_query.total_views * 100) / 1
        else
          0.0  # Explicitly use a float
        end

      # First and last watched dates
      watch_dates =
        from(ps in subquery(base_playback_query),
          select: %{
            first_watched: min(ps.start_time),
            last_watched: max(ps.start_time)
          })
        |> Repo.one()

      # Users watched - should only include the current user if non-admin, or all users if admin
      users_watched_query =
        from(ps in subquery(base_playback_query),
          join: u in User, on: ps.user_id == u.id,
          group_by: u.id,
          select: %{
            user_id: u.id,
            jellyfin_user_id: u.jellyfin_id,
            user_name: u.name,
            view_count: count(ps.id),
            total_watch_time: sum(ps.play_duration),
            last_watched: max(ps.start_time)
          })

      users_watched = Repo.all(users_watched_query)

      # Watch history - similar filter as for users_watched
      watch_history_query =
        from(ps in subquery(base_playback_query),
          join: u in User, on: ps.user_id == u.id,
          order_by: [desc: ps.start_time],
          select: %{
            id: ps.id,
            user_id: u.id,
            user_name: u.name,
            start_time: ps.start_time,
            play_duration: ps.play_duration,
            percent_complete: ps.percent_complete,
            completed: ps.completed,
            client_name: ps.client_name,
            device_name: ps.device_name,
            jellyfin_user_id: u.jellyfin_id,
            jellyfin_item_id: ps.item_jellyfin_id,
            jellyfin_series_id: ps.series_jellyfin_id,
            jellyfin_season_id: ps.season_jellyfin_id
          })

      watch_history = Repo.all(watch_history_query)

      # Watch count by month - filtered similarly
      watch_count_by_month =
        from(ps in subquery(base_playback_query),
          group_by: [fragment("date_trunc('month', ?)", ps.start_time)],
          order_by: [asc: fragment("date_trunc('month', ?)", ps.start_time)],
          select: %{
            month: fragment("date_trunc('month', ?)", ps.start_time),
            view_count: count(ps.id),
            total_watch_time: sum(ps.play_duration)
          })
        |> Repo.all()
        |> Enum.map(fn stat ->
          # Fix: Handle both DateTime and NaiveDateTime properly
          month_date = case stat.month do
            %DateTime{} -> DateTime.to_date(stat.month)
            %NaiveDateTime{} -> NaiveDateTime.to_date(stat.month)
            other ->
              # Log unexpected format and return a fallback
              Logger.error("Unexpected datetime format: #{inspect(other)}")
              Date.utc_today()
          end

          %{
            month: Date.to_iso8601(month_date),
            view_count: stat.view_count,
            total_watch_time: stat.total_watch_time
          }
        end)

      # Combine all statistics
      %{
        item: item,
        total_views: total_stats.total_views || 0,
        total_watch_time: total_stats.total_watch_time || 0,
        completion_rate: Float.round(completion_rate, 1),
        first_watched: watch_dates.first_watched,
        last_watched: watch_dates.last_watched,
        users_watched: users_watched,
        watch_history: watch_history,
        watch_count_by_month: watch_count_by_month
      }
    end
  end

  def get_item_statistics(
        server_id,
        page \\ 1,
        search \\ nil,
        sort_by \\ :total_watch_time,
        sort_order \\ :desc,
        content_type \\ nil,
        libraries \\ nil
      ) do
    per_page = 20

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

    content_types =
      case content_type do
        "Movie" -> ["Movie"]
        "Episode" -> ["Episode"]
        "Series" -> ["Series"]
        _ -> ["Movie", "Episode", "Series"]
      end

    # First, let's create a subquery to calculate watch time for episodes grouped by series_id
    series_watch_time_subquery =
      from(i in Item,
        join: ps in PlaybackSession,
        on: ps.item_jellyfin_id == i.jellyfin_id and ps.server_id == i.server_id,
        where: i.server_id == ^server_id and i.type == "Episode" and not is_nil(i.series_id),
        group_by: i.series_id,
        select: %{
          series_id: i.series_id,
          episodes_watch_count: count(ps.id),
          episodes_total_watch_time: sum(ps.play_duration)
        }
      )

    base_query =
      from(i in Item,
        left_join: ps in PlaybackSession,
        on: ps.item_jellyfin_id == i.jellyfin_id and ps.server_id == i.server_id,
        left_join: sw in subquery(series_watch_time_subquery),
        on: i.jellyfin_id == sw.series_id,
        where: i.server_id == ^server_id and i.type in ^content_types,
        group_by: [i.id, i.jellyfin_id, i.name, i.type, sw.episodes_watch_count, sw.episodes_total_watch_time],
        select: %{
          item_id: i.jellyfin_id,
          item: i,
          watch_count: fragment("CASE WHEN ? = 'Series' THEN COALESCE(?, 0) ELSE COALESCE(COUNT(?), 0) END",
                              i.type, sw.episodes_watch_count, ps.id),
          total_watch_time: fragment("CASE WHEN ? = 'Series' THEN COALESCE(?, 0) ELSE COALESCE(SUM(?), 0) END",
                                    i.type, sw.episodes_total_watch_time, ps.play_duration)
        }
      )

    # Add library filtering if libraries parameter is present
    base_query =
      if libraries do
        from([i, ps, sw] in base_query, where: i.library_id in ^libraries)
      else
        base_query
      end

    query =
      if search do
        search_term = "%#{search}%"

        where(
          base_query,
          [i, ps, sw],
          ilike(i.name, ^search_term) or
            ilike(fragment("?::text", i.production_year), ^search_term) or
            ilike(i.season_name, ^search_term) or
            ilike(i.series_name, ^search_term)
        )
      else
        base_query
      end

    query =
      case {sort_by, sort_order} do
        {:watch_count, :asc} ->
          order_by(query, [i, ps, sw], asc: fragment("CASE WHEN ? = 'Series' THEN COALESCE(?, 0) ELSE COALESCE(COUNT(?), 0) END",
                            i.type, sw.episodes_watch_count, ps.id))

        {:watch_count, :desc} ->
          order_by(query, [i, ps, sw], desc: fragment("CASE WHEN ? = 'Series' THEN COALESCE(?, 0) ELSE COALESCE(COUNT(?), 0) END",
                            i.type, sw.episodes_watch_count, ps.id))

        {:total_watch_time, :asc} ->
          order_by(query, [i, ps, sw], asc: fragment("CASE WHEN ? = 'Series' THEN COALESCE(?, 0) ELSE COALESCE(SUM(?), 0) END",
                            i.type, sw.episodes_total_watch_time, ps.play_duration))

        {:total_watch_time, :desc} ->
          order_by(query, [i, ps, sw], desc: fragment("CASE WHEN ? = 'Series' THEN COALESCE(?, 0) ELSE COALESCE(SUM(?), 0) END",
                            i.type, sw.episodes_total_watch_time, ps.play_duration))
      end

    offset = (page - 1) * per_page

    items =
      query
      |> limit(^per_page)
      |> offset(^offset)
      |> Repo.all()

    # The total items query needs to be updated to handle the filter on content types and libraries
    total_items_query =
      from(i in Item,
        where: i.server_id == ^server_id and i.type in ^content_types,
        select: i.id
      )

    # Apply library filtering to total count query as well
    total_items_query =
      if libraries do
        from(i in total_items_query, where: i.library_id in ^libraries)
      else
        total_items_query
      end

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

    total_items = total_items_query |> Repo.aggregate(:count, :id)
    total_pages = div(total_items + per_page - 1, per_page)

    %{
      items: items,
      page: page,
      per_page: per_page,
      total_items: total_items,
      total_pages: total_pages,
      sort_by: sort_by,
      sort_order: sort_order,
      content_type: content_type,
      libraries: libraries
    }
  end

  def get_most_watched_date(stats) do
    case stats do
      [] -> nil
      _ ->
        stats
        |> Enum.group_by(
          fn stat -> DateTime.to_date(stat.date_created) end,
          fn stat -> stat.play_duration || 0 end
        )
        |> Enum.map(fn {date, durations} ->
          %{
            date: date,
            total_duration: Enum.sum(durations)
          }
        end)
        |> Enum.max_by(& &1.total_duration, fn -> %{date: nil, total_duration: 0} end)
    end
  end

  defp get_total_watch_time_db(server_id, user_id) do
    query =
      from ps in PlaybackSession,
      where: ps.server_id == ^server_id,
      select: sum(ps.play_duration)

    query = if user_id, do: query |> where([ps], ps.user_jellyfin_id == ^user_id), else: query

    Repo.one(query) || 0
  end

  defp get_most_watched_date_db(server_id, user_id) do
    query =
      from ps in PlaybackSession,
      where: ps.server_id == ^server_id,
      group_by: [fragment("date(start_time)")],
      select: %{
        date: fragment("date(start_time)"),
        total_duration: sum(ps.play_duration)
      },
      order_by: [desc: sum(ps.play_duration)],
      limit: 1

    query = if user_id, do: query |> where([ps], ps.user_jellyfin_id == ^user_id), else: query

    Repo.one(query) || %{date: nil, total_duration: 0}
  end

  defp get_top_watched_items_db(server_id, user_id) do
    # First, get a list of distinct item types to create our categories
    item_types_query =
      from i in Item,
      where: i.server_id == ^server_id,
      distinct: i.type,
      where: not is_nil(i.type),
      select: i.type

    item_types = Repo.all(item_types_query)

    # Calculate top series separately by aggregating episodes
    series_stats = get_top_watched_series(server_id, user_id)

    # Then, for each type, get the top 10 items
    item_types
    |> Enum.reduce(%{}, fn item_type, acc ->
      query =
        from ps in PlaybackSession,
        join: i in Item, on: ps.item_jellyfin_id == i.jellyfin_id and ps.server_id == i.server_id,
        where: ps.server_id == ^server_id and i.type == ^item_type,
        group_by: [i.id, i.jellyfin_id, i.name, i.type],
        select: %{
          id: i.id,
          jellyfin_id: i.jellyfin_id,
          name: i.name,
          type: i.type,
          original_title: i.original_title,
          production_year: i.production_year,
          series_name: i.series_name,
          season_name: i.season_name,
          index_number: i.index_number,
          primary_image_tag: i.primary_image_tag,
          primary_image_aspect_ratio: i.primary_image_aspect_ratio,
          server_id: i.server_id,
          total_play_count: count(ps.id),
          total_play_duration: sum(ps.play_duration)
        },
        order_by: [desc: sum(ps.play_duration)],
        limit: 10

      query = if user_id, do: query |> where([ps], ps.user_jellyfin_id == ^user_id), else: query

      items = Repo.all(query)
      Map.put(acc, item_type, items)
    end)
    |> Map.put("Series", series_stats) # Add the series stats to the result
  end

  defp get_top_watched_series(server_id, user_id) do
    query =
      from ps in PlaybackSession,
      join: i in Item, on: ps.item_jellyfin_id == i.jellyfin_id and ps.server_id == i.server_id,
      where: ps.server_id == ^server_id and i.type == "Episode" and not is_nil(i.series_id),
      group_by: [i.series_id, i.series_name, i.server_id],
      select: %{
        jellyfin_id: i.series_id,
        name: i.series_name,
        type: "Series",
        original_title: nil,
        production_year: nil,
        series_name: i.series_name,
        season_name: nil,
        index_number: nil,
        primary_image_tag: fragment("(array_agg(?))[1]", i.series_primary_image_tag),
        primary_image_aspect_ratio: fragment("(array_agg(?))[1]", i.primary_image_aspect_ratio),
        server_id: i.server_id,
        total_play_count: count(ps.id),
        total_play_duration: sum(ps.play_duration),
        unique_episodes_watched: count(fragment("DISTINCT ?", i.jellyfin_id))
      },
      order_by: [desc: sum(ps.play_duration)],
      limit: 10

    query = if user_id, do: query |> where([ps], ps.user_jellyfin_id == ^user_id), else: query
    series = Repo.all(query)
    series = Enum.map(series, fn series_stat ->
      series_item = Repo.get_by(Item, jellyfin_id: series_stat.jellyfin_id, server_id: server_id)
      if series_item do
        %{series_stat |
          primary_image_tag: series_item.primary_image_tag || series_stat.primary_image_tag,
          primary_image_aspect_ratio: series_item.primary_image_aspect_ratio || series_stat.primary_image_aspect_ratio,
          production_year: series_item.production_year
        }
      else
        series_stat
      end
    end)

    series
  end

  defp get_average_watchtime_per_week_day_db(server_id, user_id) do
    daily_query =
      from p in PlaybackSession,
        where: p.server_id == ^server_id,
        group_by: fragment("date(?)", p.start_time),
        select: %{
          date: fragment("date(?)", p.start_time),
          total: sum(p.play_duration)
        }

    daily = Repo.all(daily_query)

    daily
    |> Enum.group_by(
        fn %{date: d} -> Date.day_of_week(d) end,
        fn %{total: t} -> t end
      )
    |> Enum.map(fn {dow, totals} ->
        sum_totals = Enum.sum(totals)
        count_items = length(totals)
        avg = sum_totals / count_items
        %{day_of_week: dow, duration: Float.round(avg, 2)}
      end)
    |> Enum.sort_by(& &1.day_of_week)
  end

  defp get_watchtime_per_week_day_db(server_id, user_id) do
    daily_query =
      from p in PlaybackSession,
        where: p.server_id == ^server_id,
        group_by: fragment("date(?)", p.start_time),
        select: %{
          date: fragment("date(?)", p.start_time),
          total: sum(p.play_duration)
        }

    daily = Repo.all(daily_query)

    daily
    |> Enum.group_by(
        fn %{date: d} -> Date.day_of_week(d) end,
        fn %{total: t} -> t end
      )
    |> Enum.map(fn {dow, totals} ->
        total_duration = Enum.sum(totals)
        %{day_of_week: dow, duration: total_duration}
      end)
    |> Enum.sort_by(& &1.day_of_week)
  end

  defp get_watchtime_per_hour_db(server_id, user_id) do
    query =
      from p in PlaybackSession,
        where: p.server_id == ^server_id,
        group_by: fragment("EXTRACT(HOUR FROM ?)", p.start_time),
        select: %{
          hour: fragment("EXTRACT(HOUR FROM ?)::integer", p.start_time),
          duration: sum(p.play_duration)
        },
        order_by: fragment("EXTRACT(HOUR FROM ?)", p.start_time)

    query = if user_id, do: query |> where([p], p.user_jellyfin_id == ^user_id), else: query

    # Get the results
    hours_data = Repo.all(query)

    # Fill in any missing hours with zero values
    complete_hours =
      Enum.reduce(0..23, %{}, fn hour, acc ->
        Map.put(acc, hour, 0)
      end)

    # Merge the actual data with the complete set
    filled_data =
      Enum.reduce(hours_data, complete_hours, fn %{hour: hour, duration: duration}, acc ->
        Map.put(acc, hour, duration)
      end)

    # Convert to final format
    Enum.map(0..23, fn hour ->
      %{
        hour: hour,
        duration: Map.get(filled_data, hour, 0)
      }
    end)
  end

  defp to_datetime(date, time \\ :beginning_of_day) do
    time_struct = if time == :end_of_day, do: Time.new!(23, 59, 59), else: Time.new!(0, 0, 0)

    date
    |> DateTime.new!(time_struct, "Etc/UTC")
  end
end
