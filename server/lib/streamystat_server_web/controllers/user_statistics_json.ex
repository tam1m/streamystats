defmodule StreamystatServerWeb.UserStatisticsJSON do
  def index(%{statistics: statistics}) do
    %{data: statistics}
  end

  def history(%{watch_activity: watch_activity}) do
    %{data: for(activity <- watch_activity, do: data(activity))}
  end

  def watchtime_per_day(%{watchtime_stats: watchtime_stats}) do
    %{
      data: watchtime_stats.watchtime_per_day
    }
  end

  defp data(activity) do
    %{
      id: activity.id,
      date_created: activity.start_time || activity.inserted_at ,
      item_id: activity.item_jellyfin_id,
      item_type: get_item_type(activity),
      item_name: activity.item_name,
      client_name: activity.client_name,
      device_name: activity.device_name,
      play_method: activity.play_method,
      play_duration: activity.play_duration,
      percent_complete: activity.percent_complete || 0,
      completed: activity.completed || false,
      series_name: activity.series_name,
      server_id: activity.server_id,
      user: get_user_data(activity)
    }
  end



  defp get_item_type(%{series_jellyfin_id: series_id}) when not is_nil(series_id), do: "Episode"
  defp get_item_type(_), do: "Movie"

  defp get_user_data(%{user: %{id: id, name: name, jellyfin_id: jellyfin_id}})
       when not is_nil(id) do
    %{
      id: id,
      name: name,
      jellyfin_id: jellyfin_id
    }
  end

  defp get_user_data(activity) do
    # Fallback for when the user relationship isn't preloaded or doesn't exist
    %{
      id: nil,
      name: activity.user_jellyfin_id,
      jellyfin_id: activity.user_jellyfin_id
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
        jellyfin_id: item.item.jellyfin_id,
        name: item.item.name,
        type: item.item.type,
        original_title: item.item.original_title,
        etag: item.item.etag,
        date_created: item.item.date_created,
        container: item.item.container,
        sort_name: item.item.sort_name,
        premiere_date: item.item.premiere_date,
        external_urls: item.item.external_urls,
        path: item.item.path,
        official_rating: item.item.official_rating,
        overview: item.item.overview,
        genres: item.item.genres,
        community_rating: item.item.community_rating,
        runtime_ticks: item.item.runtime_ticks,
        production_year: item.item.production_year,
        is_folder: item.item.is_folder,
        parent_id: item.item.parent_id,
        media_type: item.item.media_type,
        width: item.item.width,
        height: item.item.height,
        library_id: item.item.library_id,
        server_id: item.item.server_id,
        series_name: item.item.series_name,
        series_id: item.item.series_id,
        season_id: item.item.season_id,
        season_name: item.item.season_name,
        index_number: item.item.index_number,
        parent_index_number: item.item.parent_index_number,
        primary_image_tag: item.item.primary_image_tag,
        primary_image_thumb_tag: item.item.primary_image_thumb_tag,
        primary_image_logo_tag: item.item.primary_image_logo_tag,
        backdrop_image_tags: item.item.backdrop_image_tags,
        image_blur_hashes: item.item.image_blur_hashes,
        video_type: item.item.video_type,
        has_subtitles: item.item.has_subtitles,
        channel_id: item.item.channel_id,
        parent_backdrop_item_id: item.item.parent_backdrop_item_id,
        parent_backdrop_image_tags: item.item.parent_backdrop_image_tags,
        parent_thumb_item_id: item.item.parent_thumb_item_id,
        parent_thumb_image_tag: item.item.parent_thumb_image_tag,
        location_type: item.item.location_type,
        primary_image_aspect_ratio: item.item.primary_image_aspect_ratio,
        series_primary_image_tag: item.item.series_primary_image_tag,
        inserted_at: item.item.inserted_at,
        updated_at: item.item.updated_at
      },
      watch_count: item.watch_count,
      total_watch_time: item.total_watch_time
    }
  end
end
