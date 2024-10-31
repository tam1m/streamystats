defmodule StreamystatServerWeb.UserJSON do
  alias StreamystatServer.Jellyfin.User

  def index(%{users: users_with_details}) do
    %{data: for(user_data <- users_with_details, do: data(user_data, :index))}
  end

  def show(%{
        user: user,
        watch_history: watch_history,
        watch_stats: watch_stats,
        watch_time_per_day: watch_time_per_day
      }) do
    %{
      data:
        data(
          %{user: user, watch_stats: watch_stats, watch_time_per_day: watch_time_per_day},
          :show,
          watch_history
        )
    }
  end

  def me(%{user: user}) do
    %{
      id: user["Id"],
      name: user["Name"],
      server_id: user["ServerId"],
      primary_image_tag: user["PrimaryImageTag"],
      has_password: user["HasPassword"],
      has_configured_password: user["HasConfiguredPassword"],
      last_login_date: user["LastLoginDate"],
      last_activity_date: user["LastActivityDate"],
      configuration: user["Configuration"]
    }
  end

  defp data(%{user: %User{} = user, watch_stats: watch_stats}, :index) do
    %{
      id: user.id,
      jellyfin_id: user.jellyfin_id,
      name: user.name,
      watch_stats: %{
        total_watch_time: watch_stats.total_watch_time,
        total_plays: watch_stats.total_plays
      },
      watch_history: []
    }
  end

  defp data(
         %{
           user: %User{} = user,
           watch_stats: watch_stats,
           watch_time_per_day: watch_time_per_day
         },
         :show,
         watch_history
       ) do
    %{
      id: user.id,
      jellyfin_id: user.jellyfin_id,
      name: user.name,
      watch_history: watch_history,
      watch_stats: %{
        total_watch_time: watch_stats.total_watch_time,
        total_plays: watch_stats.total_plays
      },
      watch_time_per_day: watch_time_per_day
    }
  end
end
