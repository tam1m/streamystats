defmodule StreamystatServer.Contexts.Users do
  import Ecto.Query, warn: false
  alias StreamystatServer.Repo
  alias StreamystatServer.Jellyfin.Models.User
  alias StreamystatServer.Sessions.Models.PlaybackSession
  alias Decimal
  require Logger

  def get_users(server_id) do
    Repo.all(from(u in User, where: u.server_id == ^server_id))
  end

  @doc """
  Creates an initial user record from Jellyfin user data.
  This function is called when a user logs in for the first time
  before being synced through the regular sync process.
  """
  def create_initial_user(server_id, jellyfin_user) do
    Logger.debug("Creating initial user for server_id: #{inspect(server_id)}")

    # Create a basic user record with minimal information
    user_params = %{
      jellyfin_id: jellyfin_user["Id"],
      name: jellyfin_user["Name"],
      server_id: server_id,
      last_login: DateTime.utc_now(),
      total_watch_time: 0,
      play_count: 0
    }

    Logger.debug("User params with server_id #{inspect(server_id)}: #{inspect(user_params)}")

    %User{}
    |> User.changeset(user_params)
    |> Repo.insert()
    |> case do
      {:ok, user} ->
        Logger.info("Successfully created initial user: #{user.name} (#{user.jellyfin_id}) for server_id: #{inspect(server_id)}")
        {:ok, user}

      {:error, changeset} ->
        Logger.error("Failed to create initial user for server_id #{inspect(server_id)}: #{inspect(changeset.errors)}")
        {:error, changeset}
    end
  end

  def get_user(server_id, user_id) do
    Logger.debug("Getting user with ID: #{inspect(user_id)} for server: #{inspect(server_id)}")

    # First, try to find the user by jellyfin_id directly
    case Repo.get_by(User, jellyfin_id: user_id, server_id: server_id) do
      %User{} = user ->
        Logger.debug("Found user by jellyfin_id: #{user.jellyfin_id}, id: #{user.id}")
        user

      nil ->
        # If not found by jellyfin_id, try to see if it's a database ID (integer)
        case Integer.parse(user_id) do
          {id, ""} ->
            # It's a valid integer, try to find by id
            user = Repo.get_by(User, id: id, server_id: server_id)
            if user do
              Logger.debug("Found user by database id: #{user.id}")
              user
            else
              Logger.debug("No user found with database id: #{id}")
              nil
            end

          _ ->
            # Try to find by name as a last resort
            Logger.debug("Trying to find user by name: #{inspect(user_id)}")
            Repo.get_by(User, name: user_id, server_id: server_id)
        end
    end
  end

  def get_user_watch_history(server_id, user_id) do
    from(ps in PlaybackSession,
      where: ps.server_id == ^server_id and ps.user_id == ^user_id,
      order_by: [desc: ps.start_time],
      select: %{
        id: ps.id,
        item_id: ps.item_jellyfin_id,
        item_name: ps.item_name,
        series_name: ps.series_name,
        play_duration: ps.play_duration,
        date_created: ps.start_time,
        completed: ps.completed,
        percent_complete: ps.percent_complete
      }
    )
    |> Repo.all()
  end

  def get_user_watch_stats(server_id, user_id) do
    # Get total watch time
    total_watch_time =
      from(ps in PlaybackSession,
        where: ps.server_id == ^server_id and ps.user_id == ^user_id,
        select: sum(ps.play_duration)
      )
      |> Repo.one() || 0

    # Get total distinct items watched
    items_watched =
      from(ps in PlaybackSession,
        where: ps.server_id == ^server_id and ps.user_id == ^user_id,
        select: count(ps.item_jellyfin_id, :distinct)
      )
      |> Repo.one() || 0

    # Get completed items
    completed_items =
      from(ps in PlaybackSession,
        where: ps.server_id == ^server_id and ps.user_id == ^user_id and ps.completed == true,
        select: count()
      )
      |> Repo.one() || 0

    # --- Calculate Average Watch Time Per Day using Subquery ---
    daily_sums_query =
      from(ps in PlaybackSession,
        where: ps.server_id == ^server_id and ps.user_id == ^user_id,
        group_by: fragment("date(?)", ps.start_time),
        select: %{
          daily_sum: sum(ps.play_duration)
        },
        having: count(ps.id) > 0
      )

    avg_watch_time_per_day =
      from(ds in subquery(daily_sums_query),
        select: avg(ds.daily_sum)
      )
      |> Repo.one() || Decimal.new(0)

    avg_watch_time_per_day_int =
      avg_watch_time_per_day
      |> Decimal.to_float()
      |> Float.round()
      |> trunc()

    # --- End Subquery Calculation ---

    # +++ Calculate Total Plays (Number of Sessions) +++
    total_plays =
      from(ps in PlaybackSession,
        where: ps.server_id == ^server_id and ps.user_id == ^user_id,
        # Count all playback session rows for the user
        select: count(ps.id)
      )
      |> Repo.one() || 0

    # +++ End Total Plays Calculation +++

    %{
      total_watch_time: total_watch_time,
      items_watched: items_watched,
      completed_items: completed_items,
      avg_watch_time_per_day: avg_watch_time_per_day_int,
      total_plays: total_plays
    }
  end

  def get_user_watch_time_per_day(server_id, user_id) do
    thirty_days_ago = Date.add(Date.utc_today(), -30)

    from(ps in PlaybackSession,
      where:
        ps.server_id == ^server_id and ps.user_id == ^user_id and
          fragment("date(?)", ps.start_time) >= ^thirty_days_ago,
      group_by: fragment("date(?)", ps.start_time),
      select: %{
        date: fragment("date(?)", ps.start_time),
        total_duration: sum(ps.play_duration)
      },
      order_by: fragment("date(?)", ps.start_time)
    )
    |> Repo.all()
    |> Enum.map(fn %{date: date, total_duration: duration} ->
      %{
        date: Date.to_iso8601(date),
        total_duration: duration
      }
    end)
  end

  def get_user_genre_watch_time(server_id, user_id) do
    # Join with items to get genre info
    from(ps in PlaybackSession,
      join: i in StreamystatServer.Jellyfin.Models.Item,
      on: ps.item_jellyfin_id == i.jellyfin_id and ps.server_id == i.server_id,
      where: ps.server_id == ^server_id and ps.user_id == ^user_id,
      group_by: i.genres,
      select: %{
        genre: i.genres,
        total_duration: sum(ps.play_duration)
      },
      order_by: [desc: sum(ps.play_duration)],
      limit: 5
    )
    |> Repo.all()
    |> Enum.filter(fn %{genre: genre} -> genre && genre != [] end)
    |> Enum.flat_map(fn %{genre: genres, total_duration: duration} ->
      Enum.map(genres, fn genre -> %{genre: genre, total_duration: duration} end)
    end)
    |> Enum.group_by(fn %{genre: genre} -> genre end)
    |> Enum.map(fn {genre, entries} ->
      total = Enum.reduce(entries, 0, fn %{total_duration: duration}, acc -> acc + duration end)
      %{genre: genre, total_duration: total}
    end)
    |> Enum.sort_by(fn %{total_duration: duration} -> duration end, :desc)
    |> Enum.take(5)
  end

  def get_user_longest_streak(user_id) do
    # Convert sessions to days watched
    days_watched =
      from(ps in PlaybackSession,
        where: ps.user_id == ^user_id,
        distinct: fragment("date(?)", ps.start_time),
        select: fragment("date(?)", ps.start_time),
        order_by: fragment("date(?)", ps.start_time)
      )
      |> Repo.all()

    # Calculate longest streak
    calculate_longest_streak(days_watched)
  end

  # Helper to calculate streak from list of dates
  defp calculate_longest_streak([]), do: 0

  defp calculate_longest_streak(dates) do
    dates
    |> Enum.reduce({0, 0, nil}, fn date, {max_streak, current_streak, prev_date} ->
      case prev_date do
        nil ->
          {1, 1, date}

        _ ->
          if Date.diff(date, prev_date) == 1 do
            new_streak = current_streak + 1
            {max(max_streak, new_streak), new_streak, date}
          else
            {max(max_streak, current_streak), 1, date}
          end
      end
    end)
    |> then(fn {max_streak, current_streak, _} ->
      max(max_streak, current_streak)
    end)
  end
end
