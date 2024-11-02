defmodule StreamystatServer.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      StreamystatServerWeb.Telemetry,
      StreamystatServer.Repo,
      {DNSCluster,
       query: Application.get_env(:streamystat_server, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: StreamystatServer.PubSub},
      # Start the Finch HTTP client for sending emails
      {Finch, name: StreamystatServer.Finch},
      # Start a worker by calling: StreamystatServer.Worker.start_link(arg)
      # {StreamystatServer.Worker, arg},
      # Start to serve requests, typically the last entry
      StreamystatServerWeb.Endpoint,
      StreamystatServer.SyncTask,
      {Task, &start_full_sync/0}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: StreamystatServer.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    StreamystatServerWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp start_full_sync do
    # Get all servers
    servers = StreamystatServer.Servers.list_servers()

    # Start a full sync for each server
    Enum.each(servers, fn server ->
      StreamystatServer.SyncTask.full_sync(server.id)
    end)
  end
end
