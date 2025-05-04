defmodule StreamystatServer.Jellyfin.Libraries do
  alias StreamystatServer.Jellyfin.Models.Library
  alias StreamystatServer.Repo
  alias StreamystatServer.Jellyfin.Sync.Utils
  import Ecto.Query

  def get_libraries(server_id) do
    from(l in Library, where: l.server_id == ^server_id)
    |> join(:inner, [l], active in Utils.get_libraries_by_server(server_id), on: l.id == active.id)
    |> Repo.all()
  end

  def get_library(server_id, library_id) do
    from(l in Library, where: l.server_id == ^server_id and l.id == ^library_id)
    |> join(:inner, [l], active in Utils.get_libraries_by_server(server_id), on: l.id == active.id)
    |> Repo.one()
  end
end
