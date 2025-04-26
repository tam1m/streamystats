defmodule StreamystatServer.Jellyfin.Sync do
  @moduledoc """
  Coordinates synchronization between Jellyfin servers and the local database.
  Delegates to specialized sync modules for specific entity types.
  """

  alias StreamystatServer.Jellyfin.Sync.Users
  alias StreamystatServer.Jellyfin.Sync.Libraries
  alias StreamystatServer.Jellyfin.Sync.Items
  alias StreamystatServer.Jellyfin.Sync.Activities

  require Logger

  @sync_options %{
    max_library_concurrency: 2,
    db_batch_size: 1000,
    api_request_delay_ms: 100,
    item_page_size: 500,
    max_retries: 3,
    retry_initial_delay_ms: 1000,
    adaptive_throttling: true
  }

  # Delegate to specialized modules
  defdelegate sync_users(server), to: Users
  defdelegate sync_libraries(server), to: Libraries
  defdelegate sync_items(server, options \\ %{}), to: Items
  defdelegate sync_recently_added_items(server, limit \\ 20), to: Items, as: :sync_recently_added
  defdelegate sync_activities(server, options \\ %{}), to: Activities
  defdelegate sync_recent_activities(server), to: Activities, as: :sync_recent

  @doc """
  Returns the default synchronization options.
  These can be overridden by passing a map of options to the sync functions.
  """
  def default_options, do: @sync_options
end
