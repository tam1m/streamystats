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

  # Create the tables when the module is loaded
  @on_load :create_tables

  def create_tables do
    # Create the tables at module load time
    ensure_table_exists()
    :ok
  end

  # Store embedding progress for each server
  def start_progress_tracking(server_id) do
    ensure_table_exists()
    :ets.insert(:embedding_progress, {server_id, %{total: 0, processed: 0, status: "starting"}})
  rescue
    _ ->
      ensure_table_exists()
      :ets.insert(:embedding_progress, {server_id, %{total: 0, processed: 0, status: "starting"}})
  end

  def update_progress(server_id, total, processed, status \\ "processing") do
    ensure_table_exists()
    :ets.insert(:embedding_progress, {server_id, %{total: total, processed: processed, status: status}})
  rescue
    _ ->
      ensure_table_exists()
      :ets.insert(:embedding_progress, {server_id, %{total: total, processed: processed, status: status}})
  end

  def get_progress(server_id) do
    ensure_table_exists()

    case :ets.lookup(:embedding_progress, server_id) do
      [{^server_id, progress}] -> progress
      [] -> %{total: 0, processed: 0, status: "idle"}
    end
  rescue
    _ -> %{total: 0, processed: 0, status: "idle"}
  end

  # Create the table if it doesn't exist
  def ensure_table_exists do
    # Create embedding progress table
    if :ets.info(:embedding_progress) == :undefined do
      :ets.new(:embedding_progress, [:set, :public, :named_table])
    end

    # Create process registry table
    if :ets.info(:embedding_process_registry) == :undefined do
      :ets.new(:embedding_process_registry, [:set, :public, :named_table])
    end

    :ok
  rescue
    _ ->
      # If we're here, there was an error but we'll try once more to create the tables
      try do
        if :ets.info(:embedding_progress) == :undefined do
          :ets.new(:embedding_progress, [:set, :public, :named_table])
        end
      rescue
        _ -> Logger.error("Failed to create embedding_progress ETS table")
      end

      try do
        if :ets.info(:embedding_process_registry) == :undefined do
          :ets.new(:embedding_process_registry, [:set, :public, :named_table])
        end
      rescue
        _ -> Logger.error("Failed to create embedding_process_registry ETS table")
      end
  end

  # Start embedding process for a specific server with better error handling
  def start_embed_items_for_server(server_id, token) do
    # First ensure tables exist
    ensure_table_exists()

    # Check if a process is already running for this server
    case get_embedding_process(server_id) do
      nil ->
        # Start a new process and track its PID
        {:ok, pid} = Task.start(fn ->
          embed_items_for_server(server_id, token)
        end)

        # Register the process in our ETS table
        register_embedding_process(server_id, pid)

        # Start monitoring the process to update status if it crashes
        Process.monitor(pid)

        {:ok, "Embedding process started"}

      pid ->
        # Check if the process is still alive
        if Process.alive?(pid) do
          {:error, "Embedding process already running for server #{server_id}"}
        else
          # Process is dead but not unregistered, clean up and start a new one
          unregister_embedding_process(server_id)
          start_embed_items_for_server(server_id, token)
        end
    end
  end

  # Stop embedding process for a specific server
  def stop_embed_items_for_server(server_id) do
    # First ensure tables exist
    ensure_table_exists()

    case get_embedding_process(server_id) do
      nil ->
        {:error, "No embedding process running for server #{server_id}"}

      pid ->
        if Process.alive?(pid) do
          # Kill the process
          Process.exit(pid, :kill)

          # Update status to stopped
          update_progress(server_id, get_progress(server_id).total, get_progress(server_id).processed, "stopped")

          # Unregister the process
          unregister_embedding_process(server_id)

          {:ok, "Embedding process stopped"}
        else
          # Process already dead, just unregister and update status
          unregister_embedding_process(server_id)
          update_progress(server_id, get_progress(server_id).total, get_progress(server_id).processed, "stopped")

          {:ok, "Embedding process was not running"}
        end
    end
  end

  # Register an embedding process PID for a server
  defp register_embedding_process(server_id, pid) do
    ensure_table_exists()
    :ets.insert(:embedding_process_registry, {server_id, pid})
  rescue
    _ ->
      ensure_table_exists()
      :ets.insert(:embedding_process_registry, {server_id, pid})
  end

  # Unregister an embedding process for a server
  def unregister_embedding_process(server_id) do
    ensure_table_exists()
    :ets.delete(:embedding_process_registry, server_id)
  rescue
    _ -> Logger.error("Failed to unregister embedding process for server #{server_id}")
  end

  # Get the current embedding process PID for a server
  def get_embedding_process(server_id) do
    ensure_table_exists()

    case :ets.lookup(:embedding_process_registry, server_id) do
      [{^server_id, pid}] -> pid
      [] -> nil
    end
  rescue
    _ -> nil
  end

  # Initialize progress counter before starting embedding process
  def initialize_progress_counter do
    if Process.whereis(:embedding_progress_counter) do
      Agent.update(:embedding_progress_counter, fn _ -> 0 end)
    else
      {:ok, _} = Agent.start_link(fn -> 0 end, name: :embedding_progress_counter)
    end
  end

  # The main embedding function that processes items for a server
  def embed_items_for_server(server_id, token) do
    # Start tracking progress
    start_progress_tracking(server_id)

    # Initialize the progress counter
    initialize_progress_counter()

    try do
      # Get total count of ALL movies for this server
      total_movies_count =
        Repo.one(
          from(i in Item,
            where: i.type == "Movie" and i.server_id == ^server_id,
            select: count()
          )
        )

      # Get count of movies that already have embeddings
      already_embedded_count =
        Repo.one(
          from(i in Item,
            where: not is_nil(i.embedding) and
                  i.type == "Movie" and
                  i.server_id == ^server_id,
            select: count()
          )
        )

      # Get count of movies that need embeddings
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

      # Update total count - we want to track total movies vs. how many have embeddings
      update_progress(server_id, total_movies_count, already_embedded_count, "starting")
      Logger.info("Server #{server_id}: #{already_embedded_count}/#{total_movies_count} movies embedded, #{items_count} need processing")

      if items_count > 0 do
        # Initialize counter with already embedded count
        if Process.whereis(:embedding_progress_counter) do
          Agent.update(:embedding_progress_counter, fn _ -> already_embedded_count end)
        else
          {:ok, _} = Agent.start_link(fn -> already_embedded_count end, name: :embedding_progress_counter)
        end

        # Get a query for all movies without embeddings
        base_query = from i in Item,
          where: is_nil(i.embedding) and i.type == "Movie" and i.server_id == ^server_id

        # Process in chunks of 500 to avoid loading everything into memory
        chunk_size = 500

        # Process until we've handled all items
        Stream.unfold(0, fn offset ->
          if offset >= items_count do
            nil
          else
            # Get the next chunk of items
            items = base_query
              |> limit(^chunk_size)
              |> offset(^offset)
              |> Repo.all()

            # If no more items, end the stream
            if items == [] do
              nil
            else
              # Process this chunk and return the next offset
              {items, offset + length(items)}
            end
          end
        end)
        |> Stream.flat_map(fn chunk ->
          # Process each chunk in batches of @batch size
          chunk
          |> Stream.chunk_every(@batch)
        end)
        |> Stream.each(fn batch ->
          # Check if the process has been externally killed
          Process.sleep(50)

          # Update the progress counter
          processed = Agent.get_and_update(:embedding_progress_counter, fn count ->
            new_count = count + length(batch)
            {new_count, new_count}
          end)
          update_progress(server_id, total_movies_count, processed)

          case embed_batch_with_direct_api(batch, token) do
            :ok -> :ok
            {:error, reason} ->
              Logger.error("Failed to embed batch: #{inspect(reason)}")
              update_progress(server_id, total_movies_count, processed, "failed")
              # Clean up the process registry since we're exiting with an error
              unregister_embedding_process(server_id)
              raise "Batch embedding failed: #{inspect(reason)}"
          end
        end)
        |> Stream.run()

        # Update progress to completed if we got here without errors
        update_progress(server_id, total_movies_count, total_movies_count, "completed")
      else
        # No items to process, mark as completed
        update_progress(server_id, total_movies_count, total_movies_count, "completed")
      end

      # Clean up the process registry since we're done
      unregister_embedding_process(server_id)

      {:ok, "Embedding process completed"}
    rescue
      e ->
        Logger.error("Error during embedding process: #{inspect(e)}")
        Logger.error(Exception.format_stacktrace())
        # Update progress to failed
        update_progress(server_id, 0, 0, "failed")
        # Clean up the process registry since we're exiting with an error
        unregister_embedding_process(server_id)
        {:error, Exception.message(e)}
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
          :ok

        {:error, reason} ->
          Logger.error("Batch embedding failed: #{reason}")
          Logger.info("Falling back to individual processing for #{length(valid_items)} items")

          # Fall back to processing items individually
          Enum.each(valid_items, fn item ->
            embed_single_item(item, token)
            # Add a small delay between individual requests
            Process.sleep(200)
          end)
          :ok
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

  # Clean up all embedding processes - useful for application shutdown
  def cleanup_all_processes do
    ensure_table_exists()

    try do
      # Get all registered processes
      all_processes = :ets.tab2list(:embedding_process_registry)

      # Kill each process and mark status as stopped
      Enum.each(all_processes, fn {server_id, pid} ->
        if Process.alive?(pid) do
          Process.exit(pid, :shutdown)
          update_progress(server_id, get_progress(server_id).total, get_progress(server_id).processed, "stopped")
        end
        :ets.delete(:embedding_process_registry, server_id)
      end)

      Logger.info("All embedding processes cleaned up")
    rescue
      e -> Logger.error("Error while cleaning up embedding processes: #{inspect(e)}")
    end
  end
end
