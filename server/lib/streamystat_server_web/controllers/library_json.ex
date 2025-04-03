defmodule StreamystatServerWeb.LibraryJSON do
  alias StreamystatServer.Jellyfin.Models.Library

  def index(%{libraries: libraries}) do
    %{data: for(library <- libraries, do: data(library))}
  end

  def show(%{library: library}) do
    %{data: data(library)}
  end

  defp data(%Library{} = library) do
    %{
      id: library.id,
      jellyfin_id: library.jellyfin_id,
      name: library.name,
      type: library.type,
      server_id: library.server_id,
      inserted_at: library.inserted_at,
      updated_at: library.updated_at
    }
  end
end
