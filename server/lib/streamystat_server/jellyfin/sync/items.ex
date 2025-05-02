defmodule StreamystatServer.Jellyfin.Sync.Items do
  @moduledoc """
  Handles synchronization of Jellyfin media items to the local database.
  Delegates to specialized submodules for specific sync operations.
  """

  alias StreamystatServer.Jellyfin.Sync.Items.Core
  alias StreamystatServer.Jellyfin.Sync.Items.Recent
  alias StreamystatServer.Jellyfin.Sync.Items.ImageRefresh

  # Public API - delegate to specialized modules
  defdelegate sync_items(server, user_options \\ %{}), to: Core
  defdelegate sync_recently_added(server, limit \\ 50), to: Recent
  defdelegate refresh_item_images(server, jellyfin_id), to: ImageRefresh
  defdelegate refresh_items_images(server, jellyfin_ids), to: ImageRefresh
end
