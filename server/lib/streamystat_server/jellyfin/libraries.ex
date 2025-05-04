defmodule StreamystatServer.Jellyfin.Libraries do
  alias StreamystatServer.Jellyfin.Models.Library
  alias StreamystatServer.Repo
  alias StreamystatServer.Jellyfin.Sync.Utils
  import Ecto.Query

  @doc """
  Gets all libraries for a server.
  """
  def get_libraries(server_id) do
    from(l in Library, where: l.server_id == ^server_id)
    |> join(:inner, [l], active in subquery(Utils.get_libraries_by_server(server_id)), on: l.id == active.id)
    |> Repo.all()
  end

  @doc """
  Gets a library by its ID and server ID.
  """
  def get_library(id, server_id) do
    from(l in Library, where: l.id == ^id and l.server_id == ^server_id)
    |> join(:inner, [l], active in subquery(Utils.get_libraries_by_server(server_id)), on: l.id == active.id)
    |> Repo.one()
  end
end
