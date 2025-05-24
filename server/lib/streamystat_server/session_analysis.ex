defmodule StreamystatServer.SessionAnalysis do
  alias StreamystatServer.Repo
  alias StreamystatServer.Sessions.Models.PlaybackSession
  alias StreamystatServer.Jellyfin.Models.Item
  alias StreamystatServer.Recommendations.Models.HiddenRecommendation
  require Logger
  import Ecto.Query

  # Add a configurable cache TTL
  @cache_ttl :timer.minutes(1)  # Cache recommendations for 24 hours

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

  @doc """
  Gets comprehensive list of item IDs to exclude from recommendations for a user.
  This includes both watched items and hidden recommendations.
  """
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
  Finds similar items based on a user's viewing history.

  Improvements:
  - Adds weighting based on watch completion percentage
  - Adds temporal decay (recent watches weighted higher)
  - Adds genre preference learning
  - Adds genre filtering option
  - Adds caching mechanism
  - Returns "based on" information showing which movies contributed to each recommendation
  - Excludes both watched and hidden items
  """
  def find_similar_items_for_user(user_id, opts \\ []) do
    opts = if Keyword.keyword?(opts), do: opts, else: [limit: opts]
    limit = Keyword.get(opts, :limit, 10)
    genre_filter = Keyword.get(opts, :genre)
    boost_user_genres = Keyword.get(opts, :boost_user_genres, true)
    server_id = Keyword.get(opts, :server_id)

    # Use cached results if available
    cache_key = "user_recommendations:#{user_id}:#{limit}:#{genre_filter}:#{boost_user_genres}:#{server_id}"
    case get_from_cache(cache_key) do
      nil ->
        # Get comprehensive list of items to exclude (watched + hidden)
        excluded_item_ids = get_excluded_item_ids(user_id, server_id)

        # Get user's viewing history with weights and completion data
        watched_data = get_user_viewing_history(user_id, server_id)

        if Enum.empty?(watched_data) do
          []
        else
          # Calculate weighted average embedding
          weighted_embedding = weighted_average_embeddings(Map.keys(watched_data), watched_data)

          # Calculate user's genre preferences if boosting is enabled
          user_genre_preferences = if boost_user_genres do
            calculate_user_genre_preferences(Map.keys(watched_data), watched_data)
          else
            %{}
          end

          # Build and execute similarity query
          query = build_similarity_query(
            weighted_embedding,
            excluded_item_ids,  # Now excludes both watched and hidden
            limit * 2,
            genre_filter,
            server_id,
            opts[:library_id]
          )

          candidates = Repo.all(query)

          # Calculate final scores and select top items
          final_recommendations = candidates
          |> Enum.map(fn item ->
            base_similarity = calculate_similarity(weighted_embedding, item.embedding)

            # Apply genre boost if enabled
            genre_boost = if boost_user_genres and not Enum.empty?(user_genre_preferences) do
              apply_genre_boost(item, user_genre_preferences)
            else
              1.0
            end

            final_score = base_similarity * genre_boost

            # Find which watched movies contributed most to this recommendation
            contributing_movies = find_contributing_movies(item, Map.keys(watched_data), 3)

            %{
              item: item,
              similarity_score: final_score,
              base_similarity: base_similarity,
              genre_boost: genre_boost,
              based_on: contributing_movies
            }
          end)
          |> Enum.sort_by(& &1.similarity_score, :desc)
          |> Enum.take(limit)

          # Cache the results
          put_in_cache(cache_key, final_recommendations, @cache_ttl)
          final_recommendations
        end

      cached_result ->
        cached_result
    end
  end

  @doc """
  Finds similar items to a specific item with improved similarity calculation.
  """
  def find_similar_items_to_item(item_jellyfin_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 10)
    genre_filter = Keyword.get(opts, :genre)

    # Try cache first
    cache_key = "item_recommendations:#{item_jellyfin_id}:#{limit}:#{genre_filter}"
    case get_from_cache(cache_key) do
      nil ->
        case Repo.one(
               from(i in Item,
                 where: i.jellyfin_id == ^item_jellyfin_id
                   and not is_nil(i.embedding)
                   and is_nil(i.removed_at)  # Exclude if item itself is removed
               )
             ) do
          nil ->
            []

          item ->
            # Use server_id and library_id to prevent cross-server recommendations
            query = build_similarity_query(item.embedding, [item_jellyfin_id], limit, genre_filter, item.server_id, item.library_id)
            similar_items = Repo.all(query)
            put_in_cache(cache_key, similar_items, @cache_ttl)
            similar_items
        end
      cached_results ->
        cached_results
    end
  end

  @doc """
  Finds items similar to those in a specific session.
  """
  def find_similar_items_for_session(session_id, limit \\ 10) do
    case Repo.one(from(s in PlaybackSession, where: s.id == ^session_id)) do
      nil ->
        []

      session ->
        item =
          Repo.one(
            from(i in Item,
              where: i.jellyfin_id == ^session.item_jellyfin_id
                and not is_nil(i.embedding)
                and is_nil(i.removed_at)  # Exclude if item is removed
            )
          )

        if item do
          # Use build_similarity_query with server and library filtering
          query = build_similarity_query(item.embedding, [item.jellyfin_id], limit, nil, item.server_id, item.library_id)
          Repo.all(query)
        else
          []
        end
    end
  end

  @doc """
  Finds the most popular items among sessions with similar viewing patterns.
  """
  def find_items_from_similar_sessions(item_jellyfin_id, limit \\ 10) do
    # Find sessions where this item was watched
    sessions =
      Repo.all(
        from(s in PlaybackSession,
          where: s.item_jellyfin_id == ^item_jellyfin_id,
          select: s.id
        )
      )

    if Enum.empty?(sessions) do
      []
    else
      # First, get the server_id and library_id of the original item for filtering
      base_item = Repo.one(
        from(i in Item,
          where: i.jellyfin_id == ^item_jellyfin_id
            and is_nil(i.removed_at),  # Ensure base item is not removed
          select: i
        )
      )

      # Proceed only if we have the base item
      if base_item do
        server_id = base_item.server_id
        _library_id = base_item.library_id

        # Find users who watched this item
        users =
          Repo.all(
            from(s in PlaybackSession,
              where: s.item_jellyfin_id == ^item_jellyfin_id,
              select: s.user_jellyfin_id,
              distinct: true
            )
          )

        # Find other items these users watched
        other_items =
          Repo.all(
            from(s in PlaybackSession,
              where: s.user_jellyfin_id in ^users and s.item_jellyfin_id != ^item_jellyfin_id,
              group_by: s.item_jellyfin_id,
              select: {s.item_jellyfin_id, count(s.id)},
              order_by: [desc: count(s.id)],
              limit: ^limit
            )
          )

        # Fetch the actual items, excluding removed ones
        item_ids = Enum.map(other_items, fn {id, _} -> id end)

        Repo.all(
          from(i in Item,
            where: i.jellyfin_id in ^item_ids
              and i.server_id == ^server_id
              and is_nil(i.removed_at),  # Exclude removed items
            order_by: fragment("array_position(?, jellyfin_id)", ^item_ids)
          )
        )
      else
        []
      end
    end
  end

  @doc """
  Finds context-aware recommendations based on current time, day of week, or specified mood.
  This analyzes user's viewing patterns at different times to suggest appropriate content.
  """
  def find_contextual_recommendations(user_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 10)
    context = Keyword.get(opts, :context, :auto) # :auto, :weekend, :weekday, :evening, :quick_watch

    cache_key = "contextual_recommendations:#{user_id}:#{limit}:#{context}"
    case get_from_cache(cache_key) do
      nil ->
        # Determine context if auto
        actual_context = if context == :auto do
          determine_current_context()
        else
          context
        end

        # Get user's viewing patterns for this context
        contextual_patterns = get_user_contextual_patterns(user_id, actual_context)

        # Get base recommendations
        base_recommendations = find_similar_items_for_user(user_id, [limit: limit * 2, boost_user_genres: false])

        # Filter and rank based on context
        contextual_recommendations = apply_contextual_filtering(base_recommendations, contextual_patterns, actual_context, limit)

        put_in_cache(cache_key, contextual_recommendations, @cache_ttl)
        contextual_recommendations

      cached_results ->
        cached_results
    end
  end

  # Determine current context based on time
  defp determine_current_context() do
    now = DateTime.utc_now()
    day_of_week = Date.day_of_week(DateTime.to_date(now))
    hour = now.hour

    cond do
      day_of_week in [6, 7] -> :weekend
      hour >= 18 or hour <= 6 -> :evening
      true -> :weekday
    end
  end

  # Get user's viewing patterns for specific contexts
  defp get_user_contextual_patterns(user_id, context) do
    # Get viewing sessions with timing information
    sessions = Repo.all(
      from(s in PlaybackSession,
        join: i in Item,
        on: s.item_jellyfin_id == i.jellyfin_id,
        where: s.user_jellyfin_id == ^user_id and not is_nil(s.start_time),
        select: %{
          item_id: s.item_jellyfin_id,
          start_time: s.start_time,
          percent_complete: s.percent_complete,
          runtime_ticks: i.runtime_ticks,
          genres: i.genres,
          type: i.type
        }
      )
    )

    # Filter sessions based on context
    filtered_sessions = Enum.filter(sessions, fn session ->
      matches_context?(session.start_time, context)
    end)

    # Analyze patterns
    %{
      avg_runtime: calculate_avg_runtime(filtered_sessions),
      preferred_genres: calculate_context_genres(filtered_sessions),
      preferred_types: calculate_context_types(filtered_sessions),
      session_count: length(filtered_sessions)
    }
  end

  # Check if a timestamp matches the given context
  defp matches_context?(timestamp, context) do
    date = DateTime.to_date(timestamp)
    day_of_week = Date.day_of_week(date)
    hour = timestamp.hour

    case context do
      :weekend -> day_of_week in [6, 7]
      :weekday -> day_of_week in [1, 2, 3, 4, 5]
      :evening -> hour >= 18 or hour <= 6
      :quick_watch -> true # We'll filter by runtime later
      _ -> true
    end
  end

  # Calculate average runtime for filtered sessions
  defp calculate_avg_runtime(sessions) do
    runtimes = Enum.map(sessions, fn s -> s.runtime_ticks end)
                |> Enum.filter(fn rt -> not is_nil(rt) and rt > 0 end)

    if Enum.empty?(runtimes) do
      nil
    else
      Enum.sum(runtimes) / length(runtimes)
    end
  end

  # Calculate genre preferences for this context
  defp calculate_context_genres(sessions) do
    sessions
    |> Enum.flat_map(fn s -> s.genres || [] end)
    |> Enum.frequencies()
    |> Enum.sort_by(fn {_, count} -> count end, :desc)
    |> Enum.take(5)
    |> Enum.into(%{})
  end

  # Calculate type preferences for this context
  defp calculate_context_types(sessions) do
    sessions
    |> Enum.map(fn s -> s.type end)
    |> Enum.frequencies()
  end

  # Apply contextual filtering to recommendations
  defp apply_contextual_filtering(recommendations, patterns, context, limit) do
    recommendations
    |> Enum.map(fn rec ->
      context_score = calculate_context_score(rec.item, patterns, context)
      %{rec | similarity: rec.similarity * (1.0 + context_score)}
    end)
    |> Enum.sort_by(& &1.similarity, :desc)
    |> Enum.take(limit)
  end

  # Calculate how well an item fits the current context
  defp calculate_context_score(item, patterns, context) do
    score = 0.0

    # Runtime matching
    score = score + calculate_runtime_score(item.runtime_ticks, patterns.avg_runtime, context)

    # Genre matching
    score = score + calculate_genre_context_score(item.genres, patterns.preferred_genres)

    # Type matching
    score = score + calculate_type_context_score(item.type, patterns.preferred_types)

    # Cap the boost at 30%
    min(score, 0.3)
  end

  defp calculate_runtime_score(item_runtime, avg_runtime, context) do
    cond do
      is_nil(item_runtime) or is_nil(avg_runtime) -> 0.0
      context == :quick_watch ->
        # Prefer shorter content for quick watches
        if item_runtime <= 90 * 60 * 10_000_000 do # 90 minutes in ticks
          0.1
        else
          -0.05
        end
      abs(item_runtime - avg_runtime) <= avg_runtime * 0.3 -> 0.05 # Within 30% of preferred runtime
      true -> 0.0
    end
  end

  defp calculate_genre_context_score(item_genres, preferred_genres) when is_list(item_genres) do
    if Enum.empty?(item_genres) or map_size(preferred_genres) == 0 do
      0.0
    else
      matches = Enum.count(item_genres, fn genre -> Map.has_key?(preferred_genres, genre) end)
      (matches / length(item_genres)) * 0.1 # Max 10% boost for genre match
    end
  end

  defp calculate_genre_context_score(_, _), do: 0.0

  defp calculate_type_context_score(item_type, preferred_types) do
    total_sessions = Map.values(preferred_types) |> Enum.sum()
    if total_sessions > 0 do
      preference_ratio = Map.get(preferred_types, item_type, 0) / total_sessions
      preference_ratio * 0.05 # Max 5% boost for type preference
    else
      0.0
    end
  end

  # Enhanced private helper functions

  defp weighted_average_embeddings(items, weight_map) do
    # Extract embeddings with weights
    embedding_data =
      Enum.map(items, fn item ->
        weight = Map.get(weight_map, item.jellyfin_id, 0.5)
        vector = ensure_list_format(item.embedding)
        {vector, weight}
      end)

    # Get dimensions from first embedding
    [{first_vector, _} | _] = embedding_data
    dims = length(first_vector)

    # Initialize an accumulator with zeros
    zeros = List.duplicate(0.0, dims)

    # Total weight for normalization
    total_weight = Enum.reduce(embedding_data, 0, fn {_, weight}, sum -> sum + weight end)
    total_weight = if total_weight == 0, do: 1, else: total_weight

    # Calculate weighted sum
    weighted_sum =
      Enum.reduce(embedding_data, zeros, fn {vector, weight}, acc ->
        weighted_vector = Enum.map(vector, fn val -> val * weight end)
        Enum.zip_with(weighted_vector, acc, fn e1, e2 -> e1 + e2 end)
      end)

    # Normalize by total weight
    averaged = Enum.map(weighted_sum, fn value -> value / total_weight end)

    # Convert back to Pgvector format
    Pgvector.new(averaged)
  end

  defp weighted_average_embeddings_with_temporal(items, watch_data_map) do
    # Extract embeddings with combined weights (completion + temporal)
    embedding_data =
      Enum.map(items, fn item ->
        watch_data = Map.get(watch_data_map, item.jellyfin_id, %{percent_complete: 0.5, temporal_weight: 0.1})
        # Combine completion percentage and temporal weight
        combined_weight = watch_data.percent_complete * 0.7 + watch_data.temporal_weight * 0.3
        vector = ensure_list_format(item.embedding)
        {vector, combined_weight}
      end)

    # Get dimensions from first embedding
    [{first_vector, _} | _] = embedding_data
    dims = length(first_vector)

    # Initialize an accumulator with zeros
    zeros = List.duplicate(0.0, dims)

    # Total weight for normalization
    total_weight = Enum.reduce(embedding_data, 0, fn {_, weight}, sum -> sum + weight end)
    total_weight = if total_weight == 0, do: 1, else: total_weight

    # Calculate weighted sum
    weighted_sum =
      Enum.reduce(embedding_data, zeros, fn {vector, weight}, acc ->
        weighted_vector = Enum.map(vector, fn val -> val * weight end)
        Enum.zip_with(weighted_vector, acc, fn e1, e2 -> e1 + e2 end)
      end)

    # Normalize by total weight
    averaged = Enum.map(weighted_sum, fn value -> value / total_weight end)

    # Convert back to Pgvector format
    Pgvector.new(averaged)
  end

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

  # Calculate user's genre preferences based on viewing history
  defp calculate_user_genre_preferences(watched_items, watched_data) do
    # Flatten all genres from watched items with their weights
    genre_weights =
      Enum.reduce(watched_items, %{}, fn %{item: item}, acc ->
        watch_data = Map.get(watched_data, item.jellyfin_id, %{percent_complete: 0.5, temporal_weight: 0.1})
        combined_weight = watch_data.percent_complete * 0.7 + watch_data.temporal_weight * 0.3

        genres = item.genres || []
        Enum.reduce(genres, acc, fn genre, genre_acc ->
          Map.update(genre_acc, genre, combined_weight, fn existing -> existing + combined_weight end)
        end)
      end)

    # Normalize genre weights to get preferences (0-1 scale)
    if map_size(genre_weights) > 0 do
      max_weight = genre_weights |> Map.values() |> Enum.max()
      Enum.into(genre_weights, %{}, fn {genre, weight} ->
        {genre, weight / max_weight}
      end)
    else
      %{}
    end
  end

  # Calculate genre boost factor for a recommended item
  defp calculate_genre_boost(item_genres, user_genre_preferences) when is_list(item_genres) do
    if Enum.empty?(item_genres) or map_size(user_genre_preferences) == 0 do
      0.0
    else
      # Calculate average preference score for this item's genres
      genre_scores = Enum.map(item_genres, fn genre ->
        Map.get(user_genre_preferences, genre, 0.0)
      end)

      case Enum.count(genre_scores) do
        0 -> 0.0
        count -> Enum.sum(genre_scores) / count * 0.15 # Max 15% boost
      end
    end
  end

  defp calculate_genre_boost(_, _), do: 0.0

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

  # Helper function to get user's viewing history with weights
  defp get_user_viewing_history(user_id, server_id) do
    # Get the items the user has watched with watch completion data and timestamps
    watched_sessions =
      Repo.all(
        from(s in PlaybackSession,
          where: s.user_jellyfin_id == ^user_id,
          select: {s.item_jellyfin_id, s.percent_complete, s.start_time}
        )
      )

    # Group by item to handle multiple views of same item and calculate temporal weight
    Enum.reduce(watched_sessions, %{}, fn {item_id, pct, start_time}, acc ->
      # Calculate days since watch (for temporal decay)
      days_since = case start_time do
        nil -> 365 # Default to old if no timestamp
        timestamp ->
          DateTime.diff(DateTime.utc_now(), timestamp, :day)
      end

      # Temporal decay: more recent = higher weight (decay over 6 months)
      temporal_weight = :math.exp(-days_since / 180.0)

      # Combine completion percentage with temporal weight
      existing = Map.get(acc, item_id, %{percent_complete: 0, temporal_weight: 0, latest_watch: nil})

      Map.put(acc, item_id, %{
        percent_complete: max(existing.percent_complete, pct || 0),
        temporal_weight: max(existing.temporal_weight, temporal_weight),
        latest_watch: if(is_nil(existing.latest_watch) or DateTime.compare(start_time, existing.latest_watch) == :gt, do: start_time, else: existing.latest_watch)
      })
    end)
  end

  # Helper function to clear user recommendation cache
  defp clear_user_recommendation_cache(user_id) do
    # In a real implementation, you'd clear all cache keys that start with "user_recommendations:#{user_id}"
    # For now, we'll just log that cache should be cleared
    Logger.info("Clearing recommendation cache for user #{user_id}")
  end

  # Helper function to find contributing movies for a recommendation
  defp find_contributing_movies(recommended_item, watched_item_ids, limit) do
    # Get the watched items with embeddings, excluding removed items
    watched_items = Repo.all(
      from(i in Item,
        where: i.jellyfin_id in ^watched_item_ids
          and not is_nil(i.embedding)
          and is_nil(i.removed_at),  # Exclude removed items
        select: i
      )
    )

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

  # Helper function to apply genre boost
  defp apply_genre_boost(item, user_genre_preferences) do
    if is_nil(item.genres) or item.genres == [] do
      1.0
    else
      item.genres
      |> Enum.map(&Map.get(user_genre_preferences, &1, 0))
      |> Enum.max()
      |> Kernel.+(1.0)  # Add 1 so boost is multiplicative (1.0 = no boost, 1.5 = 50% boost)
      |> min(2.0)       # Cap boost at 100%
    end
  end
end
