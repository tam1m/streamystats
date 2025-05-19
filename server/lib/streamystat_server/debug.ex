defmodule StreamystatServer.Debug do
  @moduledoc """
  Debug utility functions for troubleshooting recommendation system
  """
  require Logger
  alias StreamystatServer.Repo
  alias StreamystatServer.Sessions.Models.PlaybackSession
  alias StreamystatServer.Jellyfin.Models.Item
  import Ecto.Query

  @doc """
  Diagnoses recommendation system issues for a specific user
  """
  def diagnose_recommendations(user_id) do
    # Check playback sessions for user
    sessions = get_user_sessions(user_id)

    # Check items with embeddings
    all_items_with_embeddings = count_all_items_with_embeddings()

    # Check user's watched items with embeddings
    user_items = get_user_watched_items_with_embeddings(user_id)

    # Check recommendation cache
    cache_exists = check_recommendation_cache()

    # Return diagnostic report
    %{
      sessions_count: length(sessions),
      all_items_with_embeddings_count: all_items_with_embeddings,
      user_watched_items_with_embeddings: length(user_items),
      recommendation_cache_exists: cache_exists,
      recommendation_cache_info: cache_info(),
      session_sample: Enum.take(sessions, 3),
      user_watched_items_sample: Enum.take(user_items, 3)
    }
  end

  # Private helper functions
  defp get_user_sessions(user_id) do
    Repo.all(
      from(s in PlaybackSession,
        where: s.user_id == ^user_id,
        select: %{id: s.id, item_id: s.item_jellyfin_id, percent_complete: s.percent_complete}
      )
    )
  end

  defp count_all_items_with_embeddings do
    Repo.aggregate(
      from(i in Item,
        where: not is_nil(i.embedding)
      ),
      :count
    )
  end

  defp get_user_watched_items_with_embeddings(user_id) do
    # Get the items the user has watched
    watched_item_ids =
      Repo.all(
        from(s in PlaybackSession,
          where: s.user_id == ^user_id,
          select: s.item_jellyfin_id,
          distinct: true
        )
      )

    # Get those items with embeddings
    Repo.all(
      from(i in Item,
        where: i.jellyfin_id in ^watched_item_ids and not is_nil(i.embedding),
        select: %{id: i.jellyfin_id, title: i.name, server_id: i.server_id, library_id: i.library_id}
      )
    )
  end

  defp check_recommendation_cache do
    # Check if the ETS table exists
    case :ets.info(:recommendation_cache) do
      :undefined -> false
      _ -> true
    end
  end

  defp cache_info do
    case :ets.info(:recommendation_cache) do
      :undefined -> "Cache table does not exist"
      info when is_list(info) ->
        # Convert keyword list to map before using Map.take
        info_map = Map.new(info)
        Map.take(info_map, [:size, :memory, :type, :named_table, :protection])
      other -> other
    end
  end
end
