defmodule StreamystatServerWeb.StatisticsJSON do
  def index(%{statistics: statistics}) do
    %{data: statistics}
  end

  def history(%{watch_activity: watch_activity}) do
    %{data: for(activity <- watch_activity, do: data(activity))}
  end

  defp data(activity) do
    %{
      id: activity.id,
      date_created: activity.date_created,
      item_id: activity.item_id,
      item_type: activity.item_type,
      item_name: activity.item_name,
      client_name: activity.client_name,
      device_name: activity.device_name,
      play_method: activity.play_method,
      play_duration: activity.play_duration,
      server_id: activity.server_id,
      user: %{
        id: activity.user.id,
        name: activity.user.name,
        jellyfin_id: activity.user.jellyfin_id
      }
    }
  end
end
