defmodule StreamystatServer.SessionAnalysis do
  alias StreamystatServer.Repo
  alias StreamystatServer.Sessions.Models.PlaybackSession
  alias StreamystatServer.Jellyfin.Models.Item
  alias StreamystatServer.Recommendations.Models.HiddenRecommendation
  require Logger
  import Ecto.Query

  @doc """
  Removes all embeddings from jellyfin_items table for a specific server.
  Returns {:ok, count} where count is the number of items updated.
  """
  def remove_all_embeddings(server_id) do
    try do
      {count, _} = Repo.update_all(
        from(i in Item, where: not is_nil(i.embedding) and i.server_id == ^server_id),
        set: [embedding: nil]
      )
      {:ok, count}
    rescue
      e ->
        Logger.error("Failed to remove embeddings for server #{server_id}: #{inspect(e)}")
        {:error, "Failed to remove embeddings: #{Exception.message(e)}"}
    end
  end

  @doc """
  Hides a recommendation for a specific user
  """
  def hide_recommendation(user_id, item_jellyfin_id, server_id) do
    attrs = %{
      user_jellyfin_id: user_id,
      item_jellyfin_id: item_jellyfin_id,
      server_id: server_id,
      hidden_at: DateTime.utc_now()
    }

    %HiddenRecommendation{}
    |> HiddenRecommendation.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, hidden_rec} ->
        # Clear relevant caches
        clear_user_recommendation_cache(user_id)
        {:ok, hidden_rec}
      {:error, changeset} ->
        {:error, changeset}
    end
  end

  # Gets comprehensive list of item IDs to exclude from recommendations for a user.
  # This includes both watched items and hidden recommendations.
  defp get_excluded_item_ids(user_id, server_id) do
    # Get all items the user has watched (any completion percentage)
    watched_item_ids = Repo.all(
      from(s in PlaybackSession,
        where: s.user_jellyfin_id == ^user_id,
        select: s.item_jellyfin_id,
        distinct: true
      )
    )

    # Get all items the user has hidden
    hidden_item_ids = Repo.all(
      from(h in HiddenRecommendation,
        where: h.user_jellyfin_id == ^user_id and h.server_id == ^server_id,
        select: h.item_jellyfin_id
      )
    )

    # Combine both lists and remove duplicates
    (watched_item_ids ++ hidden_item_ids) |> Enum.uniq()
  end

  @doc """
  Simple recommendation system that finds items similar to what the user watched recently.
  - Excludes both watched and hidden items
  """
  def find_similar_items_for_user(user_id, opts \\ []) do
    opts = if Keyword.keyword?(opts), do: opts, else: [limit: opts]
    limit = Keyword.get(opts, :limit, 10)
    server_id = Keyword.get(opts, :server_id)

    # Use simple cache key without complex options
    cache_key = "simple_recommendations:#{user_id}:#{limit}:#{server_id}"
    case get_from_cache(cache_key) do
      nil ->
        # Get items to exclude (watched + hidden)
        excluded_item_ids = get_excluded_item_ids(user_id, server_id)

        # Get user's recently watched items (last 10)
        recently_watched = get_recently_watched_items(user_id, server_id, 10)

        if Enum.empty?(recently_watched) do
          []
        else
          # Calculate simple average embedding from recently watched items
          average_embedding = simple_average_embeddings(recently_watched)

          # Build basic similarity query
          query = build_similarity_query(
            average_embedding,
            excluded_item_ids,
            limit,
            nil,  # no genre filter
            server_id,
            nil   # no library filter
          )

          recommendations = Repo.all(query)
          |> Enum.map(fn item ->
            similarity = calculate_similarity(average_embedding, item.embedding)

            # Find top 3 recently watched items that contributed to this recommendation
            contributing_items = find_contributing_movies(item, recently_watched, 3)

            %{
              item: item,
              similarity: similarity,
              based_on: contributing_items
            }
          end)
          |> Enum.sort_by(& &1.similarity, :desc)
          |> Enum.take(limit)

          # Cache the results for 1 hour
          put_in_cache(cache_key, recommendations, 3600)
          recommendations
        end

      cached_result ->
        cached_result
    end
  end

  # Helper function to get user's recently watched items
  defp get_recently_watched_items(user_id, server_id, limit) do
    Repo.all(
      from(s in PlaybackSession,
        join: i in Item,
        on: s.item_jellyfin_id == i.jellyfin_id and s.server_id == i.server_id,
        where: s.user_jellyfin_id == ^user_id
          and s.server_id == ^server_id
          and not is_nil(i.embedding)
          and is_nil(i.removed_at),
        order_by: [desc: s.start_time],
        limit: ^limit,
        select: i,
        distinct: i.jellyfin_id
      )
    )
  end

  # Simple average of embeddings without complex weighting
  defp simple_average_embeddings(items) when is_list(items) and length(items) > 0 do
    # Convert all embeddings to list format
    embeddings = Enum.map(items, fn item ->
      ensure_list_format(item.embedding)
    end)

    # Get dimensions from first embedding
    [first_embedding | _] = embeddings
    dims = length(first_embedding)

    # Calculate simple average
    averaged =
      0..(dims - 1)
      |> Enum.map(fn dim_index ->
        # Sum values at this dimension across all embeddings
        sum = Enum.reduce(embeddings, 0, fn embedding, acc ->
          acc + Enum.at(embedding, dim_index)
        end)
        # Average by number of embeddings
        sum / length(embeddings)
      end)

    # Convert back to Pgvector format
    Pgvector.new(averaged)
  end

  defp simple_average_embeddings(_), do: nil

  defp ensure_list_format(embedding) do
    if is_list(embedding), do: embedding, else: Pgvector.to_list(embedding)
  end

  defp build_similarity_query(embedding, excluded_item_ids, limit, genre_filter, server_id \\ nil, library_id \\ nil) do
    # Start with a simple query structure - exclude items without embeddings, removed items, and user-excluded items
    query = from(i in Item,
      where: i.jellyfin_id not in ^excluded_item_ids
        and not is_nil(i.embedding)
        and is_nil(i.removed_at)  # Exclude removed items
    )

    # Apply genre filter if provided
    query = if genre_filter do
      from(i in query, where: fragment("? && ?", i.genres, ^[genre_filter]))
    else
      query
    end

    # Apply server and library filters if provided
    query = if server_id do
      from(i in query, where: i.server_id == ^server_id)
    else
      query
    end

    query = if library_id do
      from(i in query, where: i.library_id == ^library_id)
    else
      query
    end

    # Add similarity calculation and ordering
    from(i in query,
      select: %{
        item: i,
        similarity: fragment("1 - (? <=> ?)", i.embedding, ^embedding)
      },
      order_by: [desc: fragment("1 - (? <=> ?)", i.embedding, ^embedding)],
      limit: ^limit
    )
  end

  # Helper function to calculate cosine similarity between two embeddings
  defp calculate_similarity(embedding1, embedding2) do
    # Convert embeddings to list format if needed
    vec1 = ensure_list_format(embedding1)
    vec2 = ensure_list_format(embedding2)

    # Calculate cosine similarity: (a · b) / (|a| * |b|)
    dot_product = Enum.zip_with(vec1, vec2, fn a, b -> a * b end) |> Enum.sum()
    magnitude1 = :math.sqrt(Enum.map(vec1, fn x -> x * x end) |> Enum.sum())
    magnitude2 = :math.sqrt(Enum.map(vec2, fn x -> x * x end) |> Enum.sum())

    if magnitude1 == 0 or magnitude2 == 0 do
      0.0
    else
      dot_product / (magnitude1 * magnitude2)
    end
  end

  # Cache functions
  defp get_from_cache(key) do
    try do
      case :ets.lookup(:recommendation_cache, key) do
        [{^key, value, expiry}] ->
          if System.system_time(:second) < expiry do
            value
          else
            # Delete expired entry
            :ets.delete(:recommendation_cache, key)
            nil
          end
        [] -> nil
      end
    rescue
      ArgumentError ->
        # Table doesn't exist, gracefully handle it
        Logger.warning("ETS table :recommendation_cache not found when trying to get #{key}")
        try_create_cache_table()
        nil
    end
  end

  defp put_in_cache(key, value, ttl) do
    try do
      expiry = System.system_time(:second) + ttl
      :ets.insert(:recommendation_cache, {key, value, expiry})
    rescue
      ArgumentError ->
        # Table doesn't exist, try to create it
        Logger.warning("ETS table :recommendation_cache not found when trying to put #{key}")
        if try_create_cache_table() do
          # Try again if table was created
          expiry = System.system_time(:second) + ttl
          :ets.insert(:recommendation_cache, {key, value, expiry})
        end
    end
  end

  # Attempt to create the cache table if it doesn't exist
  defp try_create_cache_table do
    try do
      :ets.new(:recommendation_cache, [:set, :public, :named_table])
      Logger.info("Created missing :recommendation_cache ETS table")
      true
    rescue
      ArgumentError ->
        # Table might have been created in the meantime by another process
        case :ets.info(:recommendation_cache) do
          :undefined ->
            Logger.error("Failed to create :recommendation_cache ETS table")
            false
          _ -> true
        end
    end
  end

  # Helper function to clear user recommendation cache
  defp clear_user_recommendation_cache(user_id) do
    # In a real implementation, you'd clear all cache keys that start with "user_recommendations:#{user_id}"
    # For now, we'll just log that cache should be cleared
    Logger.info("Clearing recommendation cache for user #{user_id}")
  end

  # Helper function to find contributing movies for a recommendation
  defp find_contributing_movies(recommended_item, watched_items, limit) when is_list(watched_items) do
    # Calculate similarity between recommendation and each watched item
    watched_items
    |> Enum.map(fn watched_item ->
      similarity = calculate_similarity(recommended_item.embedding, watched_item.embedding)
      %{item: watched_item, similarity: similarity}
    end)
    |> Enum.sort_by(& &1.similarity, :desc)
    |> Enum.take(limit)
    |> Enum.map(& &1.item)
  end
end
