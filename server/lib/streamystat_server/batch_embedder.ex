defmodule StreamystatServer.BatchEmbedder do
  alias StreamystatServer.Repo
  alias StreamystatServer.Jellyfin.Models.Item
  alias StreamystatServer.EmbeddingProvider.OpenAI
  alias StreamystatServer.Servers
  require Logger
  import Ecto.Query

  # Adjust these parameters based on your usage patterns and API limits
  # How many items to process in one API call
  @batch 20
  # Lower concurrency to avoid rate limits
  @concurrency 3
  # Extended timeout for batches with retries
  @timeout 60_000
  # Small delay between batches to avoid rate limiting
  @delay_between_batches 500
  
  # Store embedding progress for each server
  def start_progress_tracking(server_id) do
    try do
      :ets.insert(:embedding_progress, {server_id, %{total: 0, processed: 0, status: "starting"}})
    catch
      _, _ -> ensure_table_exists()
    end
  end
  
  def update_progress(server_id, total, processed, status \\ "processing") do
    try do
      :ets.insert(:embedding_progress, {server_id, %{total: total, processed: processed, status: status}})
    catch
      _, _ -> ensure_table_exists()
    end
  end
  
  def get_progress(server_id) do
    try do
      case :ets.lookup(:embedding_progress, server_id) do
        [{^server_id, progress}] -> progress
        [] -> %{total: 0, processed: 0, status: "idle"}
      end
    catch
      _, _ -> 
        ensure_table_exists()
        %{total: 0, processed: 0, status: "idle"}
    end
  end
  
  # Create the table if it doesn't exist
  defp ensure_table_exists do
    try do
      if !:ets.info(:embedding_progress) do
        :ets.new(:embedding_progress, [:set, :public, :named_table])
      end
    catch
      _, _ -> 
        # If we still can't create it, just log the error
        Logger.error("Failed to create or access embedding_progress ETS table")
    end
  end

  def embed_all_items do
    Logger.info("Starting batch embedding process for movies without embeddings")

    # Get servers with OpenAI API tokens
    servers_with_tokens =
      Repo.all(
        from(s in Servers.Models.Server,
          where: not is_nil(s.open_ai_api_token),
          select: {s.id, s.open_ai_api_token}
        )
      )


    if Enum.empty?(servers_with_tokens) do
      Logger.warning("No servers with OpenAI API tokens found. Skipping embedding.")
      :ok
    else
      # Process each server
      Enum.each(servers_with_tokens, fn {server_id, token} ->
        embed_items_for_server(server_id, token)
      end)
    end
  end

  def embed_items_for_server(server_id, token) do
    # Start tracking progress
    start_progress_tracking(server_id)
    
    items_count =
      Repo.one(
        from(i in Item,
          where:
            is_nil(i.embedding) and
              i.type == "Movie" and
              i.server_id == ^server_id,
          select: count()
        )
      )

    # Update total count
    update_progress(server_id, items_count, 0, "starting")
    Logger.info("Found #{items_count} movies without embeddings for server #{server_id}")

    if items_count > 0 do
      # Process counter to track progress
      processed_count = 0
      
      # Process items in smaller chunks without a global transaction
      items = Item
      |> where([i], is_nil(i.embedding) and i.type == "Movie" and i.server_id == ^server_id)
      |> limit(500) # Process in chunks of 500 items at a time
      |> Repo.all()
      
      items
      |> Stream.chunk_every(@batch, @batch)
      |> Task.async_stream(
        fn batch -> 
          result = embed_batch_with_direct_api(batch, token)
          
          # Update progress after each batch
          processed_count = min(processed_count + length(batch), items_count)
          update_progress(server_id, items_count, processed_count)
          
          result
        end,
        max_concurrency: @concurrency,
        ordered: false,
        timeout: @timeout
      )
      |> Stream.run()

      # Mark as completed
      update_progress(server_id, items_count, items_count, "completed")
      Logger.info("Completed batch embedding process for movies on server #{server_id}")
    else
      # No items to process
      update_progress(server_id, 0, 0, "completed")
    end
  end

  # This function processes a batch by sending texts together to the OpenAI API
  defp embed_batch_with_direct_api(items, token) do
    # Extract texts for all items in batch
    texts_with_items = Enum.map(items, fn item -> {build_text(item), item} end)

    # Process only non-empty texts
    valid_texts_with_items =
      Enum.filter(texts_with_items, fn {text, _} ->
        text != nil && text != ""
      end)

    valid_texts = Enum.map(valid_texts_with_items, fn {text, _} -> text end)
    valid_items = Enum.map(valid_texts_with_items, fn {_, item} -> item end)

    if Enum.empty?(valid_texts) do
      Logger.warning("No valid texts found in batch of #{length(items)} items")
      :ok
    else
      # Use the OpenAI batch embedding functionality with the server's token
      case OpenAI.embed_batch(valid_texts, token) do
        {:ok, embeddings} ->
          # Process successful results
          Enum.zip(valid_items, embeddings)
          |> Enum.each(fn {item, embedding} ->
            # Ensure embedding is a raw list before casting to vector
            embedding_data = case embedding do
              {:ok, vector} -> vector # Handle case where it's already wrapped in {:ok, vector}
              _ when is_list(embedding) -> embedding # Regular list data
              _ -> nil # Skip invalid data
            end
            
            if embedding_data do
              # Cast to Pgvector format safely
              case Pgvector.Ecto.Vector.cast(embedding_data) do
                {:ok, vector} ->
                  Repo.update_all(
                    from(i in Item, where: i.id == ^item.id),
                    set: [embedding: vector]
                  )
                _ ->
                  Logger.error("Failed to cast embedding for item #{item.id} - invalid format")
              end
            else
              Logger.error("Invalid embedding data for item #{item.id}")
            end
          end)

          # Add a small delay to avoid rate limiting
          Process.sleep(@delay_between_batches)
          Logger.info("Successfully embedded batch of #{length(valid_items)} items")

        {:error, reason} ->
          Logger.error("Batch embedding failed: #{reason}")
          Logger.info("Falling back to individual processing for #{length(valid_items)} items")

          # Fall back to processing items individually
          Enum.each(valid_items, fn item ->
            embed_single_item(item, token)
            # Add a small delay between individual requests
            Process.sleep(200)
          end)
      end
    end
  end

  # Process a single item as a fallback
  defp embed_single_item(item, token) do
    text = build_text(item)

    if text != nil && text != "" do
      try do
        case OpenAI.embed(text, token) do
          {:ok, embedding} ->
            # Ensure embedding is a raw list before casting to vector
            embedding_data = case embedding do
              {:ok, vector} -> vector # Handle case where it's already wrapped in {:ok, vector}
              _ when is_list(embedding) -> embedding # Regular list data
              _ -> nil # Skip invalid data
            end
            
            if embedding_data do
              # Cast to Pgvector format safely
              case Pgvector.Ecto.Vector.cast(embedding_data) do
                {:ok, vector} ->
                  Repo.update_all(
                    from(i in Item, where: i.id == ^item.id),
                    set: [embedding: vector]
                  )
                  Logger.info("Successfully embedded item #{item.id}")
                _ ->
                  Logger.error("Failed to cast embedding for item #{item.id} - invalid format")
              end
            else
              Logger.error("Invalid embedding data for item #{item.id}")
            end

          {:error, reason} ->
            Logger.error("Failed to embed item #{item.id}: #{reason}")
        end
      rescue
        e ->
          Logger.error("Exception when embedding item #{item.id}: #{inspect(e)}")
      end
    else
      Logger.warning("Skipping item #{item.id} - empty text")
    end
  end

  defp build_text(%Item{} = item) do
    people_text =
      if is_list(item.people) do
        item.people
        |> Enum.map(fn person ->
          name = Map.get(person, "Name", "")
          role = Map.get(person, "Role", "")
          type = Map.get(person, "Type", "")

          cond do
            # Skip if no name
            name == "" -> ""
            type == "" && role == "" -> name
            type == "" && role != "" -> "#{name} as #{role}"
            role == "" -> "#{name} (#{String.downcase(type)})"
            true -> "#{name} as #{role} (#{String.downcase(type)})"
          end
        end)
        # Remove empty strings
        |> Enum.filter(&(&1 != ""))
        |> Enum.join(", ")
      else
        item.people
      end

    [
      item.name,
      item.genres,
      item.type,
      item.community_rating,
      item.series_name,
      item.season_name,
      item.production_year,
      item.overview,
      people_text
    ]
    |> Enum.filter(&(&1 && &1 != ""))
    |> Enum.join(" ")
  end
end
