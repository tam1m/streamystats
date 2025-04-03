defmodule StreamystatServer.Jellyfin.Libraries do
  alias StreamystatServer.Jellyfin.Models.Library
  alias StreamystatServer.Repo
  import Ecto.Query

  def get_libraries(server_id) do
    from(l in Library, where: l.server_id == ^server_id)
    |> Repo.all()
  end

  def get_library(server_id, library_id) do
    from(l in Library, where: l.server_id == ^server_id and l.id == ^library_id)
    |> Repo.one()
  end
end
