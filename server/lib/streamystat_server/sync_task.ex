defmodule StreamystatServer.SyncTask do
  use GenServer
  alias StreamystatServer.JellyfinSync
  alias StreamystatServer.Servers
  alias StreamystatServer.Servers.Server
  alias StreamystatServer.Servers.SyncLog
  alias StreamystatServer.Repo
  require Logger

  @type server_id :: String.t()
  @type sync_type :: String.t()
  @type sync_result :: {:ok, Server.t()} | {:error, atom()}

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    {:ok, task_supervisor} = Task.Supervisor.start_link()
    schedule_full_sync()
    schedule_partial_sync()
    {:ok, %{task_supervisor: task_supervisor}}
  end

  @spec partial_sync(server_id()) :: :ok
  def partial_sync(server_id),
    do: GenServer.cast(__MODULE__, {:partial_sync, server_id})

  @spec full_sync(server_id()) :: :ok
  def full_sync(server_id), do: GenServer.cast(__MODULE__, {:full_sync, server_id})

  @spec sync_users(server_id()) :: :ok
  def sync_users(server_id), do: GenServer.cast(__MODULE__, {:sync_users, server_id})

  @spec sync_libraries(server_id()) :: :ok
  def sync_libraries(server_id), do: GenServer.cast(__MODULE__, {:sync_libraries, server_id})

  @spec sync_items(server_id()) :: :ok
  def sync_items(server_id), do: GenServer.cast(__MODULE__, {:sync_items, server_id})

  @spec sync_playback_stats(server_id()) :: :ok
  def sync_playback_stats(server_id),
    do: GenServer.cast(__MODULE__, {:sync_playback_stats, server_id})

  @impl true
  def handle_cast({sync_type, server_id}, %{task_supervisor: supervisor} = state)
      when sync_type in [
             :partial_sync,
             :full_sync,
             :sync_users,
             :sync_libraries,
             :sync_items,
             :sync_playback_stats
           ] do
    Task.Supervisor.async_nolink(supervisor, fn ->
      perform_sync(sync_type, server_id)
    end)

    {:noreply, state}
  end

  @impl true
  def handle_info({ref, _result}, state) do
    Process.demonitor(ref, [:flush])
    {:noreply, state}
  end

  @impl true
  def handle_info(:sync, %{task_supervisor: supervisor} = state) do
    Task.Supervisor.async_nolink(supervisor, fn ->
      Servers.list_servers()
      |> Enum.each(fn server ->
        perform_sync(:full_sync, server.id)
      end)
    end)

    schedule_full_sync()
    {:noreply, state}
  end

  @impl true
  def handle_info(:partial_sync, %{task_supervisor: supervisor} = state) do
    Task.Supervisor.async_nolink(supervisor, fn ->
      Servers.list_servers()
      |> Enum.each(fn server ->
        perform_sync(:partial_sync, server.id)
      end)
    end)

    schedule_partial_sync()
    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state) do
    {:noreply, state}
  end

  defp perform_sync(sync_type, server_id) do
    with {:ok, server} <- get_server(server_id) do
      sync_log = create_sync_log(server_id, Atom.to_string(sync_type))

      try do
        case sync_type do
          :partial_sync -> perform_partial_sync(server)
          :full_sync -> perform_full_sync(server)
          :sync_users -> JellyfinSync.sync_users(server)
          :sync_libraries -> JellyfinSync.sync_libraries(server)
          :sync_items -> JellyfinSync.sync_items(server)
          :sync_playback_stats -> JellyfinSync.sync_playback_stats(server, :partial)
        end

        Logger.info("#{sync_type} completed for server #{server.name}")
        update_sync_log(sync_log, :completed)
        {:ok, server}
      rescue
        e ->
          Logger.error("Error during #{sync_type} for server #{server.name}: #{inspect(e)}")
          update_sync_log(sync_log, :failed)
          {:error, :sync_failed}
      end
    end
  end

  @spec get_server(server_id()) :: {:ok, Servers.Server.t()} | {:error, :not_found}
  defp get_server(server_id) do
    case Servers.get_server(server_id) do
      nil ->
        Logger.error("Server with ID #{server_id} not found")
        {:error, :not_found}

      server ->
        {:ok, server}
    end
  end

  defp create_sync_log(server_id, sync_type) do
    %SyncLog{}
    |> SyncLog.changeset(%{
      server_id: server_id,
      sync_type: sync_type,
      sync_started_at: NaiveDateTime.utc_now()
    })
    |> Repo.insert!()
  end

  defp update_sync_log(sync_log, status) do
    sync_log
    |> SyncLog.changeset(%{
      sync_completed_at: NaiveDateTime.utc_now(),
      status: Atom.to_string(status)
    })
    |> Repo.update!()
  end

  defp schedule_full_sync do
    # Run every 24 hours
    Process.send_after(self(), :full_sync, 24 * 60 * 60 * 1000)
  end

  defp schedule_partial_sync do
    # Run every hour
    Process.send_after(self(), :partial_sync, 60 * 1000)
  end

  defp perform_full_sync(server) do
    JellyfinSync.sync_users(server)
    JellyfinSync.sync_libraries(server)
    JellyfinSync.sync_items(server)
    JellyfinSync.sync_playback_stats(server, :full)
    :ok
  end

  defp perform_partial_sync(server) do
    # JellyfinSync.sync_users(server)
    # JellyfinSync.sync_libraries(server)
    # JellyfinSync.sync_recent_items(server)
    JellyfinSync.sync_playback_stats(server, :partial)
    :ok
  end
end
