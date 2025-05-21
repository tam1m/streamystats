# lib/streamystat_server_web/controllers/activity_json.ex

defmodule StreamystatServerWeb.ActivityJSON do
  alias StreamystatServer.Activities.Models.Activity
  alias StreamystatServer.Jellyfin.Models.User
  alias StreamystatServer.Repo

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
    # Look up user directly by jellyfin_id and server_id
    user = if activity.user_jellyfin_id,
           do: User |> Repo.get_by([jellyfin_id: activity.user_jellyfin_id, server_id: activity.user_server_id]),
           else: nil

    %{
      id: activity.id,
      jellyfin_id: activity.jellyfin_id,
      name: activity.name,
      short_overview: activity.short_overview,
      type: activity.type,
      date: activity.date,
      user_jellyfin_id: activity.user_jellyfin_id,
      user_server_id: activity.user_server_id,
      user_name: user && user.name,
      server_id: activity.server_id,
      severity: activity.severity
    }
  end
end
