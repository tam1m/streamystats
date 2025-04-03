# lib/streamystat_server_web/controllers/activity_json.ex

defmodule StreamystatServerWeb.ActivityJSON do
  alias StreamystatServer.Activities.Models.Activity

  def index(%{
        activities: activities,
        page: page,
        per_page: per_page,
        total_items: total_items,
        total_pages: total_pages
      }) do
    %{
      data: for(activity <- activities, do: data(activity)),
      page: page,
      per_page: per_page,
      total_items: total_items,
      total_pages: total_pages
    }
  end

  def data(%Activity{} = activity) do
    %{
      id: activity.id,
      jellyfin_id: activity.jellyfin_id,
      name: activity.name,
      short_overview: activity.short_overview,
      type: activity.type,
      date: activity.date,
      user_id: activity.user_id,
      server_id: activity.server_id,
      severity: activity.severity
    }
  end
end
