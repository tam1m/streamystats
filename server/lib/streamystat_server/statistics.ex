defmodule StreamystatServer.Statistics do
  import Ecto.Query, warn: false
  alias StreamystatServer.Jellyfin.PlaybackActivity
  alias StreamystatServer.Jellyfin.Item
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

  def get_item_statistics(server_id, page \\ 1, per_page \\ 20) do
    query =
      from(pa in PlaybackActivity,
        join: i in Item,
        on: pa.item_id == i.jellyfin_id and pa.server_id == i.server_id,
        where: pa.server_id == ^server_id,
        group_by: [i.id, i.jellyfin_id, i.name, i.type],
        select: %{
          item_id: i.jellyfin_id,
          item: %{
            id: i.id,
            name: i.name,
            type: i.type
          },
          watch_count: count(pa.id),
          total_watch_time: sum(pa.play_duration)
        },
        order_by: [desc: sum(pa.play_duration)]
      )

    total_query =
      from(pa in PlaybackActivity,
        join: i in Item,
        on: pa.item_id == i.jellyfin_id and pa.server_id == i.server_id,
        where: pa.server_id == ^server_id,
        select: count(i.id, :distinct)
      )

    total_items = Repo.one(total_query) || 0
    total_pages = if per_page > 0, do: ceil(total_items / per_page), else: 0

    items =
      query
      |> limit(^per_page)
      |> offset(^((page - 1) * per_page))
      |> Repo.all()

    %{
      items: items,
      page: page,
      per_page: per_page,
      total_items: total_items,
      total_pages: total_pages
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
