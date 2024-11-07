defmodule StreamystatServer.Contexts.Users do
  alias StreamystatServer.Repo
  alias StreamystatServer.Jellyfin.User
  alias StreamystatServer.Jellyfin.PlaybackActivity
  alias StreamystatServer.Jellyfin.Item
  import Ecto.Query

  def get_users(server_id) do
    Repo.all(from(u in User, where: u.server_id == ^server_id))
  end

  def get_user(server_id, user_identifier) do
    case Integer.parse(user_identifier) do
      {id, ""} ->
        # If user_identifier is a valid integer, search by id
        Repo.get_by(User, server_id: server_id, id: id)

      _ ->
        # If user_identifier is not an integer, search by name
        Repo.get_by(User, server_id: server_id, name: user_identifier)
    end
  end

  def get_user_watch_history(server_id, user_id) do
    PlaybackActivity
    |> where(server_id: ^server_id, user_id: ^user_id)
    |> order_by(desc: :date_created)
    # Limit to the last 50 activities, adjust as needed
    |> limit(50)
    |> Repo.all()
  end

  @spec get_user_watch_stats(any(), any()) :: any()
  def get_user_watch_stats(server_id, user_id) do
    query =
      from(w in PlaybackActivity,
        where: w.server_id == ^server_id and w.user_id == ^user_id,
        select: %{
          total_watch_time: sum(w.play_duration),
          total_plays: count(w.id)
        }
      )

    Repo.one(query) || %{total_watch_time: 0, total_plays: 0}
  end

  @spec get_user_watch_time_per_day(any(), any()) :: list()
  def get_user_watch_time_per_day(server_id, user_id) do
    query =
      from(w in PlaybackActivity,
        where: w.server_id == ^server_id and w.user_id == ^user_id,
        group_by: fragment("DATE(date_created)"),
        order_by: fragment("DATE(date_created)"),
        select: {
          fragment("DATE(date_created)"),
          sum(w.play_duration)
        }
      )

    Repo.all(query)
    |> Enum.map(fn {date, watch_time} ->
      %{
        date: Date.to_string(date),
        watch_time: watch_time
      }
    end)
  end

  @spec get_user_genre_watch_time(integer(), integer()) :: list()
  def get_user_genre_watch_time(server_id, user_id) do
    query =
      from(pa in PlaybackActivity,
        join: i in Item,
        on: pa.item_id == i.jellyfin_id,
        where: pa.server_id == ^server_id and pa.user_id == ^user_id,
        left_lateral_join: g in fragment("SELECT unnest(?) AS genre", i.genres),
        group_by: g.genre,
        select: %{
          genre: g.genre,
          watch_time: sum(pa.play_duration)
        }
      )

    Repo.all(query)
  end

  def get_user_longest_streak(user_id) do
    query =
      from(pa in PlaybackActivity,
        where: pa.user_id == ^user_id,
        select: pa.date_created,
        order_by: [asc: pa.date_created]
      )

    dates = Repo.all(query)

    dates
    |> Enum.map(&NaiveDateTime.to_date/1)
    |> Enum.uniq()
    |> calculate_longest_streak()
  end

  defp calculate_longest_streak(dates) do
    dates
    |> Enum.reduce({0, 0, nil}, fn date, {max_streak, current_streak, last_date} ->
      case last_date do
        nil ->
          {1, 1, date}

        _ ->
          days_diff = Date.diff(date, last_date)

          if days_diff == 1 do
            new_streak = current_streak + 1
            {max(max_streak, new_streak), new_streak, date}
          else
            {max(max_streak, current_streak), 1, date}
          end
      end
    end)
    |> elem(0)
  end
end
