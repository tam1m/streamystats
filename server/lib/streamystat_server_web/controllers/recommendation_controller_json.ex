defmodule StreamystatServerWeb.RecommendationJSON do
  @doc """
  Renders a list of recommended items
  """
  def recommendations(%{items: items}) do
    %{
      data: Enum.map(items, &prepare_item_for_json/1),
      count: length(items)
    }
  end

  @doc """
  Renders a single item
  """
  def item(%{item: item}) do
    prepare_item_for_json(item)
  end

  @doc """
  Renders an error
  """
  def error(%{error: message}) do
    %{error: message}
  end

  # Convert struct to map and remove fields that can't be serialized
  # Handle the new format with based_on and source_group information
  defp prepare_item_for_json(%{item: item, similarity: similarity, based_on: based_on, source_group: source_group}) do
    # Keep the nested structure instead of flattening
    item_map =
      item
      |> Map.from_struct()
      |> Map.drop([:__meta__, :__struct__, :embedding, :library, :server])

    # Prepare based_on items
    based_on_items =
      Enum.map(based_on, fn based_item ->
        based_item
        |> Map.from_struct()
        |> Map.drop([:__meta__, :__struct__, :embedding, :library, :server])
      end)

    # Return the structure that matches your TypeScript interface
    %{
      item: item_map,
      similarity: similarity,
      based_on: based_on_items
      # Remove source_group to match your interface
    }
  end

  # Handle the format with based_on information but no source_group
  defp prepare_item_for_json(%{item: item, similarity: similarity, based_on: based_on}) do
    item_map =
      item
      |> Map.from_struct()
      |> Map.drop([:__meta__, :__struct__, :embedding, :library, :server])

    based_on_items =
      Enum.map(based_on, fn based_item ->
        based_item
        |> Map.from_struct()
        |> Map.drop([:__meta__, :__struct__, :embedding, :library, :server])
      end)

    # Return the structure that matches your TypeScript interface
    %{
      item: item_map,
      similarity: similarity,
      based_on: based_on_items
    }
  end

  # Handle the original format with just similarity score
  defp prepare_item_for_json(%{item: item, similarity: similarity}) do
    item_map =
      item
      |> Map.from_struct()
      |> Map.drop([:__meta__, :__struct__, :embedding, :library, :server])

    %{
      item: item_map,
      similarity: similarity,
      based_on: []  # Empty array for consistency
    }
  end

  # Handle regular items without similarity score (fallback)
  defp prepare_item_for_json(item) when is_struct(item) do
    item_map =
      item
      |> Map.from_struct()
      |> Map.drop([:__meta__, :__struct__, :embedding, :library, :server])

    %{
      item: item_map,
      similarity: 0.0,
      based_on: []
    }
  end

  # Fallback for any other format
  defp prepare_item_for_json(item) do
    item
  end
end
