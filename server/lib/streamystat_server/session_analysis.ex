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
    |> Repo.insert(on_conflict: :nothing, conflict_target: [:user_jellyfin_id, :item_jellyfin_id, :server_id])
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
  Diverse recommendation system that finds items similar to what the user watched recently.
  - Divides recent watch history into groups for more diverse recommendations
  - Excludes both watched and hidden items
  """
  def find_similar_items_for_user(user_id, opts \\ []) do
    opts = if Keyword.keyword?(opts), do: opts, else: [limit: opts]
    limit = Keyword.get(opts, :limit, 10)
    server_id = Keyword.get(opts, :server_id)

    Logger.info("Finding similar items for user #{user_id} with limit #{limit} and server_id #{server_id}")

    # Use simple cache key without complex options
    cache_key = "diverse_recommendations:#{user_id}:#{limit}:#{server_id}"
    case get_from_cache(cache_key) do
      nil ->
        Logger.debug("Cache miss for key: #{cache_key}")

        # Get items to exclude (watched + hidden)
        excluded_item_ids = get_excluded_item_ids(user_id, server_id)
        Logger.debug("Found #{length(excluded_item_ids)} items to exclude")

        # Get user's recently watched items (increased to 20 for more diversity)
        recently_watched = get_recently_watched_items(user_id, server_id, 20)
        Logger.debug("Found #{length(recently_watched)} recently watched items")

        if Enum.empty?(recently_watched) do
          Logger.info("No recently watched items found for user #{user_id}")
          []
        else
          # Get diverse recommendations from different groups of recent movies
          diverse_recommendations = get_diverse_recommendations(
            recently_watched,
            excluded_item_ids,
            limit,
            server_id
          )
          Logger.info("Generated #{length(diverse_recommendations)} diverse recommendations")

          # Cache the results for 1 hour
          put_in_cache(cache_key, diverse_recommendations, 3600)
          Logger.debug("Cached recommendations for key: #{cache_key}")
          diverse_recommendations
        end

      cached_result ->
        Logger.debug("Cache hit for key: #{cache_key}")
        cached_result
    end
  end

  # Get diverse recommendations by sampling from different groups of recently watched items
  defp get_diverse_recommendations(recently_watched, excluded_item_ids, limit, server_id) do
    Logger.info("=== get_diverse_recommendations DEBUG ===")
    Logger.info("recently_watched count: #{length(recently_watched)}")
    Logger.info("excluded_item_ids count: #{length(excluded_item_ids)}")
    Logger.info("limit: #{limit}")
    Logger.info("server_id: #{server_id}")

    # Define different sampling strategies for diversity
    sampling_strategies = [
      # Last 2 movies (most recent)
      %{name: "recent", items: Enum.take(recently_watched, 2), weight: 0.4},
      # Next 2 movies (offset 2-4)
      %{name: "mid_recent", items: Enum.slice(recently_watched, 2, 2), weight: 0.3},
      # Next 3 movies (offset 4-7)
      %{name: "older", items: Enum.slice(recently_watched, 4, 3), weight: 0.2},
      # Random sample from remaining
      %{name: "random", items: Enum.slice(recently_watched, 7, 5) |> Enum.shuffle() |> Enum.take(2), weight: 0.1}
    ]

    Logger.info("Original sampling_strategies:")
    Enum.with_index(sampling_strategies, fn strategy, index ->
      Logger.info("  [#{index}] name: #{strategy.name}, items_count: #{length(strategy.items)}, weight: #{strategy.weight}")
      Logger.info("      keys: #{inspect(Map.keys(strategy))}")
    end)

    # Calculate how many recommendations to get from each strategy
    Logger.info("Starting to map strategies with counts...")

    recommendations_per_strategy = Enum.map(sampling_strategies, fn strategy ->
      Logger.info("Processing strategy: #{strategy.name}")
      Logger.info("  Original strategy keys: #{inspect(Map.keys(strategy))}")

      count = max(1, round(limit * strategy.weight))
      Logger.info("  Calculated count: #{count}")

      # Use Map.put instead of map update syntax
      result = Map.put(strategy, :count, count)
      Logger.info("  Result after Map.put: keys = #{inspect(Map.keys(result))}")

      result
    end)

    Logger.info("Final recommendations_per_strategy:")
    Enum.with_index(recommendations_per_strategy, fn strategy, index ->
      Logger.info("  [#{index}] #{inspect(strategy)}")
      Logger.info("  [#{index}] keys: #{inspect(Map.keys(strategy))}")
    end)

    # Get recommendations from each strategy
    Logger.info("Starting flat_map over recommendations_per_strategy...")

    all_recommendations =
      recommendations_per_strategy
      |> Enum.flat_map(fn strategy ->
        Logger.info("flat_map processing strategy: #{inspect(strategy)}")
        Logger.info("flat_map strategy keys: #{inspect(Map.keys(strategy))}")
        Logger.info("flat_map strategy.name: #{inspect(Map.get(strategy, :name, "KEY_MISSING"))}")
        Logger.info("flat_map strategy.count: #{inspect(Map.get(strategy, :count, "KEY_MISSING"))}")
        Logger.info("flat_map strategy.items length: #{if Map.has_key?(strategy, :items), do: length(strategy.items), else: "KEY_MISSING"}")

        if Enum.empty?(strategy.items) do
          Logger.info("Strategy #{strategy.name} has empty items, returning []")
          []
        else
          Logger.info("Calling get_recommendations_for_group for #{strategy.name} with count: #{strategy.count}")
          try do
            result = get_recommendations_for_group(
              strategy.items,
              excluded_item_ids,
              strategy.count,
              strategy.name
            )
            Logger.info("get_recommendations_for_group returned #{length(result)} recommendations")
            result
          rescue
            e ->
              Logger.error("Error in get_recommendations_for_group for #{strategy.name}: #{inspect(e)}")
              Logger.error("Strategy that caused error: #{inspect(strategy)}")
              reraise e, __STACKTRACE__
          end
        end
      end)
      |> Enum.uniq_by(fn rec -> rec.item.jellyfin_id end)  # Remove duplicates

    Logger.info("Total recommendations before sorting: #{length(all_recommendations)}")

    # Sort by similarity and take the requested limit
    final_recommendations = all_recommendations
    |> Enum.sort_by(& &1.similarity, :desc)
    |> Enum.take(limit)

    Logger.info("Final recommendations count: #{length(final_recommendations)}")
    Logger.info("=== get_diverse_recommendations DEBUG END ===")

    final_recommendations
  end

  # Get recommendations for a specific group of items
  defp get_recommendations_for_group(items, excluded_item_ids, count, _group_name) do
    # Calculate average embedding for this group
    average_embedding = simple_average_embeddings(items)

    if is_nil(average_embedding) do
      []
    else
      # Build similarity query for this group
      query = build_similarity_query(
        average_embedding,
        excluded_item_ids,
        count * 2,  # Get more results to ensure diversity
        nil,  # no genre filter
        nil,  # no server filter
        nil   # no library filter
      )

      Repo.all(query)
      |> Enum.map(fn result ->
        # Handle both new format (with item/similarity keys) and old format
        item = case result do
          %{item: item, similarity: _similarity} -> item
          item -> item
        end

        similarity = calculate_similarity(average_embedding, item.embedding)

        # Find top 3 items from this group that contributed to this recommendation
        contributing_items = find_contributing_movies(item, items, 3)

        # Log the format we're creating
        recommendation = %{
          item: item,
          similarity: similarity,
          based_on: contributing_items
          # Remove source_group to match TypeScript interface
        }

        Logger.info("Created recommendation format: #{inspect(Map.keys(recommendation))}")
        Logger.info("  item type: #{inspect(item.__struct__)}")
        Logger.info("  similarity type: #{inspect(similarity)}")
        Logger.info("  based_on count: #{length(contributing_items)}")
        Logger.info("  based_on first item type: #{if length(contributing_items) > 0, do: inspect(hd(contributing_items).__struct__), else: "empty"}")

        recommendation
      end)
      |> Enum.sort_by(& &1.similarity, :desc)
      |> Enum.take(count)
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

  defp build_similarity_query(embedding, excluded_item_ids, limit, genre_filter, server_id, library_id) do
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
    try do
      # Get all cache keys and find the ones that match this user
      pattern = "diverse_recommendations:#{user_id}:"

      # Get all keys from the ETS table
      case :ets.tab2list(:recommendation_cache) do
        keys_and_values ->
          keys_to_delete =
            keys_and_values
            |> Enum.filter(fn {key, _value, _expiry} ->
              String.starts_with?(key, pattern)
            end)
            |> Enum.map(fn {key, _value, _expiry} -> key end)

          # Delete all matching keys
          Enum.each(keys_to_delete, fn key ->
            :ets.delete(:recommendation_cache, key)
          end)

          Logger.info("Cleared #{length(keys_to_delete)} recommendation cache entries for user #{user_id}")
      end
    rescue
      ArgumentError ->
        # Table doesn't exist, nothing to clear
        Logger.info("No recommendation cache table found, nothing to clear for user #{user_id}")
    end
  end

  # Helper function to find contributing movies for a recommendation
  defp find_contributing_movies(recommended_item, watched_items, limit) when is_list(watched_items) do
    Logger.info("find_contributing_movies called with:")
    Logger.info("  recommended_item: #{recommended_item.name}")
    Logger.info("  watched_items count: #{length(watched_items)}")
    Logger.info("  limit: #{limit}")

    # Calculate similarity between recommendation and each watched item
    result = watched_items
    |> Enum.map(fn watched_item ->
      similarity = calculate_similarity(recommended_item.embedding, watched_item.embedding)
      %{item: watched_item, similarity: similarity}
    end)
    |> Enum.sort_by(& &1.similarity, :desc)
    |> Enum.take(limit)
    |> Enum.map(& &1.item)  # <- This should return just the items

    Logger.info("find_contributing_movies returning #{length(result)} items")
    Logger.info("  first item type: #{if length(result) > 0, do: inspect(hd(result).__struct__), else: "empty"}")

    result
  end
end
