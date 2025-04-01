defmodule StreamystatServerWeb.StatisticsJSON do
  def unwatched(%{
        items: items,
        page: page,
        per_page: per_page,
        total_items: total_items,
        total_pages: total_pages
      }) do
    %{
      data: for(item <- items, do: unwatched_item_data(item)),
      page: page,
      per_page: per_page,
      total_items: total_items,
      total_pages: total_pages
    }
  end

  defp unwatched_item_data(item) do
    %{
      id: item.id,
      jellyfin_id: item.jellyfin_id,
      name: item.name,
      type: item.type,
      production_year: item.production_year,
      series_name: item.series_name,
      season_name: item.season_name,
      index_number: item.index_number,
      date_created: item.date_created,
      runtime_ticks: item.runtime_ticks
    }
  end
end
