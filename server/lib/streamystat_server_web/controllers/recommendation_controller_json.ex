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
  defp prepare_item_for_json(%{item: item, similarity: similarity}) do
    # Handle the case where item is wrapped with similarity score
    item_map =
      item
      |> Map.from_struct()
      |> Map.drop([:__meta__, :__struct__, :embedding, :library, :server])

    # Add similarity score to the response
    Map.put(item_map, :similarity, similarity)
  end

  # Handle regular items without similarity score
  defp prepare_item_for_json(item) when is_struct(item) do
    item
    |> Map.from_struct()
    |> Map.drop([:__meta__, :__struct__, :embedding, :library, :server])
  end

  # Fallback for any other format
  defp prepare_item_for_json(item) do
    item
  end
end
