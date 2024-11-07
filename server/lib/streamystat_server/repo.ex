defmodule StreamystatServer.Repo do
  use Ecto.Repo,
    otp_app: :streamystat_server,
    adapter: Ecto.Adapters.Postgres

  use Scrivener, page_size: 20
end
