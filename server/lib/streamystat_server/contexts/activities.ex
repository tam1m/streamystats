defmodule StreamystatServer.Contexts.Activities do
  import Ecto.Query, warn: false
  alias StreamystatServer.Repo
  alias StreamystatServer.Jellyfin.Activity

  def list_activities(server, opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 20)

    Activity
    |> where([a], a.server_id == ^server.id)
    |> order_by([a], desc: a.date)
    |> Repo.paginate(page: page, page_size: per_page)
  end
end
