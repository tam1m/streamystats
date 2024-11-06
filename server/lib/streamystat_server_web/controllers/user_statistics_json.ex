defmodule StreamystatServerWeb.UserStatisticsJSON do
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

  def items(%{item_stats: item_stats}) do
    %{
      data: Enum.map(item_stats.items, &item_data/1),
      page: item_stats.page,
      per_page: item_stats.per_page,
      total_items: item_stats.total_items,
      total_pages: item_stats.total_pages
    }
  end

  def library_stats(%{stats: stats}) do
    %{data: stats}
  end

  defp item_data(item) do
    %{
      item_id: item.item_id,
      item: %{
        id: item.item.id,
        name: item.item.name,
        type: item.item.type,
        season_name: item.item.season_name,
        series_name: item.item.series_name,
        production_year: item.item.production_year
      },
      watch_count: item.watch_count,
      total_watch_time: item.total_watch_time
    }
  end
end
