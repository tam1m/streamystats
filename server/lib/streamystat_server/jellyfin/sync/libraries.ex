defmodule StreamystatServer.Jellyfin.Sync.Libraries do
  @moduledoc """
  Handles synchronization of Jellyfin libraries to the local database.
  """

  require Logger

  alias StreamystatServer.Repo
  alias StreamystatServer.Jellyfin.Client
  alias StreamystatServer.Jellyfin.Models.Library
  alias StreamystatServer.Jellyfin.Sync.Utils

  @doc """
  Synchronizes libraries from a Jellyfin server to the local database.
  Returns {:ok, count}, {:partial, count, errors}, or {:error, reason}.
  """
  def sync_libraries(server) do
    Logger.info("Starting library sync for server #{server.name}")

    case Client.get_libraries(server) do
      {:ok, jellyfin_libraries} ->
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
      inserted_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second),
      updated_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
    }
  end
end
