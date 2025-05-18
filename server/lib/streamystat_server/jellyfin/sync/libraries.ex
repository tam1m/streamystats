defmodule StreamystatServer.Jellyfin.Sync.Libraries do
  @moduledoc """
  Handles synchronization of Jellyfin libraries to the local database.
  """

  require Logger

  alias StreamystatServer.Repo
  alias StreamystatServer.Jellyfin.Client
  alias StreamystatServer.Jellyfin.Models.Library
  alias StreamystatServer.Jellyfin.Sync.Utils
  import Ecto.Query

  @doc """
  Synchronizes libraries from a Jellyfin server to the local database.
  Returns {:ok, count}, {:partial, count, errors}, or {:error, reason}.
  """
  def sync_libraries(server) do
    Logger.info("Starting library sync for server #{server.name}")

    case Client.get_libraries(server) do
      {:ok, jellyfin_libraries} ->
        # Get current libraries from Jellyfin
        current_jellyfin_ids = Enum.map(jellyfin_libraries, & &1["Id"])

        # Mark libraries that no longer exist as removed
        # Only proceed with this if we have at least one library
        if length(current_jellyfin_ids) > 0 do
          from(l in Library, where: l.server_id == ^server.id and l.jellyfin_id not in ^current_jellyfin_ids)
          |> Repo.update_all(set: [removed_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)])
        else
          Logger.warning("No libraries found - skipping library removal step")
        end

        # Process existing libraries
        libraries = Enum.map(jellyfin_libraries, &map_jellyfin_library(&1, server.id))

        result =
          Enum.reduce(libraries, {0, []}, fn library, {count, errors} ->
            case Repo.insert(Library.changeset(%Library{}, library),
                   on_conflict: {:replace_all_except, [:id]},
                   conflict_target: [:jellyfin_id, :server_id]
                 ) do
              {:ok, _} ->
                {count + 1, errors}

              {:error, changeset} ->
                Logger.warning("Error inserting library: #{inspect(changeset.errors)}")
                {count, [changeset.errors | errors]}
            end
          end)

        case result do
          {count, []} ->
            Logger.info("Synced #{count} libraries")
            {:ok, count}

          {count, errors} ->
            Logger.warning("Synced #{count} libraries with #{length(errors)} errors")
            Logger.warning("Errors: #{inspect(errors)}")
            {:partial, count, errors}
        end

      {:error, reason} ->
        Logger.error("Failed to sync libraries: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Maps a Jellyfin library JSON object to a map suitable for database insertion.
  """
  def map_jellyfin_library(jellyfin_library, server_id) do
    type = jellyfin_library["CollectionType"] || "unknown"

    sanitized_type =
      case Utils.sanitize_string(type) do
        nil -> "unknown"
        sanitized -> sanitized
      end

    %{
      jellyfin_id: jellyfin_library["Id"],
      name: Utils.sanitize_string(jellyfin_library["Name"]),
      type: sanitized_type,
      server_id: server_id,
      removed_at: nil,
      inserted_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second),
      updated_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
    }
  end
end
