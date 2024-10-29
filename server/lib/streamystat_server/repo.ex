defmodule StreamystatServer.Repo do
  use Ecto.Repo,
    otp_app: :streamystat_server,
    adapter: Ecto.Adapters.Postgres
end
