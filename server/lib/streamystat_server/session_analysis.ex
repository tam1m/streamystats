defmodule StreamystatServer.SessionAnalysis do
  alias StreamystatServer.Repo
  alias StreamystatServer.Sessions.Models.PlaybackSession
  alias StreamystatServer.Jellyfin.Models.Item
  require Logger
  import Ecto.Query

  @doc """
  Finds similar items based on a user's viewing history.
  """
  def find_similar_items_for_user(user_id, limit \\ 10) do
    # Get the items the user has watched
    watched_item_ids =
      Repo.all(
        from(s in PlaybackSession,
          where: s.user_id == ^user_id,
          distinct: true,
          select: s.item_jellyfin_id
        )
      )

    # Get the embeddings for those items
    watched_items =
      Repo.all(
        from(i in Item,
          where: i.jellyfin_id in ^watched_item_ids and not is_nil(i.embedding)
        )
      )

    # If no watched items with embeddings, return empty list
    if Enum.empty?(watched_items) do
      []
    else
      # Calculate a "user taste profile" by averaging the embeddings of watched items
      combined_embedding = average_embeddings(watched_items)

      # Find similar items using the combined embedding
      similar_items = find_similar_items(combined_embedding, watched_item_ids, limit)

      # Return the list of similar items
      similar_items
    end
  end

  @doc """
  Finds similar items to a specific item.
  """
  def find_similar_items_to_item(item_jellyfin_id, limit \\ 10) do
    case Repo.one(
           from(i in Item, where: i.jellyfin_id == ^item_jellyfin_id and not is_nil(i.embedding))
         ) do
      nil ->
        []

      item ->
        find_similar_items(item.embedding, [item_jellyfin_id], limit)
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
              where: i.jellyfin_id == ^session.item_jellyfin_id and not is_nil(i.embedding)
            )
          )

        if item do
          find_similar_items(item.embedding, [item.jellyfin_id], limit)
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
      # Find users who watched this item
      users =
        Repo.all(
          from(s in PlaybackSession,
            where: s.item_jellyfin_id == ^item_jellyfin_id,
            select: s.user_id,
            distinct: true
          )
        )

      # Find other items these users watched
      other_items =
        Repo.all(
          from(s in PlaybackSession,
            where: s.user_id in ^users and s.item_jellyfin_id != ^item_jellyfin_id,
            group_by: s.item_jellyfin_id,
            select: {s.item_jellyfin_id, count(s.id)},
            order_by: [desc: count(s.id)],
            limit: ^limit
          )
        )

      # Fetch the actual items
      item_ids = Enum.map(other_items, fn {id, _} -> id end)

      Repo.all(
        from(i in Item,
          where: i.jellyfin_id in ^item_ids,
          order_by: fragment("array_position(?, jellyfin_id)", ^item_ids)
        )
      )
    end
  end

  # Private helper functions

  defp average_embeddings(items) do
    # Extract embeddings and convert to lists for manipulation
    embedding_lists =
      Enum.map(items, fn item ->
        # Convert Pgvector to list if it's not already
        if is_list(item.embedding) do
          item.embedding
        else
          # Extract vector values from the Pgvector struct
          # This assumes Pgvector exposes a way to access the raw values
          # If not, check the Pgvector library documentation for the correct approach
          Pgvector.to_list(item.embedding)
        end
      end)

    # Calculate the dimensionality (length of first embedding)
    [first | _] = embedding_lists
    dims = length(first)

    # Initialize an accumulator with zeros
    zeros = List.duplicate(0.0, dims)

    # Sum the vectors
    summed =
      Enum.reduce(embedding_lists, zeros, fn embedding, acc ->
        Enum.zip_with(embedding, acc, fn e1, e2 -> e1 + e2 end)
      end)

    # Divide by count to get average
    count = length(embedding_lists)

    # Create the averaged vector
    averaged = Enum.map(summed, fn value -> value / count end)

    # Convert back to Pgvector format
    Pgvector.new(averaged)
  end

  defp find_similar_items(embedding, excluded_item_ids, limit) do
    # Use the pgvector extension to find similar items by cosine similarity
    Repo.all(
      from(i in Item,
        where: i.jellyfin_id not in ^excluded_item_ids and not is_nil(i.embedding),
        order_by: fragment("embedding <=> ?", ^embedding),
        limit: ^limit,
        select: i
      )
    )
  end
end
