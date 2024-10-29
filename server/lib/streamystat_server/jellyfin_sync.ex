defmodule StreamystatServer.JellyfinSync do
  import Ecto.Query
  alias StreamystatServer.Repo
  alias StreamystatServer.JellyfinClient
  alias StreamystatServer.Jellyfin.Library
  alias StreamystatServer.Jellyfin.Item
  alias StreamystatServer.Servers.Server
  alias StreamystatServer.Jellyfin.User
  alias StreamystatServer.Jellyfin.PlaybackActivity
  require Logger

  def sync_users(server) do
    Logger.info("Starting user sync for server #{server.name}")

    case JellyfinClient.get_users(server) do
      {:ok, jellyfin_users} ->
        users_data = Enum.map(jellyfin_users, &map_jellyfin_user(&1, server.id))

        Repo.transaction(fn ->
          {count, _} =
            Repo.insert_all(
              StreamystatServer.Jellyfin.User,
              users_data,
              on_conflict: {:replace, [:name]},
              conflict_target: [:jellyfin_id, :server_id]
            )

          count
        end)
        |> case do
          {:ok, count} ->
            Logger.info("Successfully synced #{count} users for server #{server.name}")
            {:ok, count}

          {:error, reason} ->
            Logger.error("Failed to sync users for server #{server.name}: #{inspect(reason)}")
            {:error, reason}
        end

      {:error, reason} ->
        Logger.error("Failed to sync users for server #{server.name}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def sync_libraries(server) do
    Logger.info("Starting library sync for server #{server.name}")

    case JellyfinClient.get_libraries(server) do
      {:ok, jellyfin_libraries} ->
        Logger.info("Received #{length(jellyfin_libraries)} libraries from Jellyfin")
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

  def sync_items(server) do
    Logger.info("Starting item sync for all libraries")

    case JellyfinClient.get_libraries(server) do
      {:ok, libraries} ->
        results =
          Enum.map(libraries, fn library ->
            sync_library_items(server, library["Id"])
          end)

        total_count = Enum.sum(Enum.map(results, fn {_, count, _} -> count end))
        total_errors = Enum.flat_map(results, fn {_, _, errors} -> errors end)

        case total_errors do
          [] ->
            Logger.info("Synced #{total_count} items across all libraries")
            {:ok, total_count}

          _ ->
            Logger.warning(
              "Synced #{total_count} items with #{length(total_errors)} errors across all libraries"
            )

            Logger.warning("Errors: #{inspect(total_errors)}")
            {:partial, total_count, total_errors}
        end

      {:error, reason} ->
        Logger.error("Failed to fetch libraries: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp sync_library_items(server, jellyfin_library_id) do
    Logger.info("Starting item sync for Jellyfin library #{jellyfin_library_id}")

    with {:ok, jellyfin_items} <- JellyfinClient.get_items(server, jellyfin_library_id),
         {:ok, library} <- get_library_by_jellyfin_id(jellyfin_library_id, server.id) do
      Logger.info(
        "Received #{length(jellyfin_items)} items from Jellyfin for library #{library.name}"
      )

      items = Enum.map(jellyfin_items, &map_jellyfin_item(&1, library.id, server.id))

      try do
        # Insert items in batches of 5000
        {total_count, _} =
          Enum.chunk_every(items, 5000)
          |> Enum.reduce({0, nil}, fn batch, {acc_count, _} ->
            {count, _} =
              Repo.insert_all(
                Item,
                batch,
                on_conflict: {:replace_all_except, [:id]},
                conflict_target: [:jellyfin_id, :library_id]
              )

            {acc_count + count, nil}
          end)

        Logger.info("Synced #{total_count} items for library #{library.name}")
        {:ok, total_count, []}
      rescue
        e ->
          Logger.error("Error syncing items for library #{library.name}: #{inspect(e)}")
          {:error, 0, [inspect(e)]}
      end
    else
      {:error, :library_not_found} ->
        Logger.error(
          "Library with Jellyfin ID #{jellyfin_library_id} not found for server #{server.id}"
        )

        {:error, 0, ["Library not found"]}

      {:error, reason} ->
        Logger.error(
          "Failed to sync items for Jellyfin library #{jellyfin_library_id}: #{inspect(reason)}"
        )

        {:error, 0, [reason]}
    end
  end

  def sync_playback_stats(server) do
    Logger.info("Starting playback stats sync for server #{server.name}")

    case check_playback_reporting_plugin(server) do
      {:ok, true} ->
        oldest_activity_date = get_oldest_playback_activity_date()

        Logger.info("Fetching playback stats since #{oldest_activity_date}")

        case JellyfinClient.get_playback_stats(server, oldest_activity_date) do
          {:ok, playback_data} ->
            insert_playback_data(playback_data, server)

          {:error, reason} ->
            Logger.error("Failed to fetch playback stats: #{inspect(reason)}")
            {:error, reason}
        end

      {:ok, false} ->
        Logger.info("Playback Reporting Plugin not detected. Skipping playback stats sync.")
        {:ok, :plugin_not_found}

      {:error, reason} ->
        Logger.error("Error checking Playback Reporting Plugin: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp check_playback_reporting_plugin(server) do
    case JellyfinClient.get_installed_plugins(server) do
      {:ok, plugins} ->
        has_plugin =
          Enum.any?(plugins, fn plugin ->
            plugin["ConfigurationFileName"] == "Jellyfin.Plugin.PlaybackReporting.xml"
          end)

        {:ok, has_plugin}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_oldest_playback_activity_date do
    Repo.one(from(p in PlaybackActivity, select: min(p.date_created)))
  end

  defp insert_playback_data(playback_data, server) do
    Logger.info("Received playback data: #{inspect(playback_data)}")

    mapped_data = Enum.map(playback_data, &map_playback_data(&1, server))

    Repo.transaction(fn ->
      Enum.reduce(mapped_data, 0, fn data, count ->
        case insert_or_update_playback_activity(data) do
          {:ok, _} -> count + 1
          {:error, _} -> count
        end
      end)
    end)
    |> case do
      {:ok, count} ->
        update_server_last_synced_id_if_needed(server, mapped_data)
        {:ok, count}

      {:error, reason} ->
        Logger.error("Transaction failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp insert_or_update_playback_activity(data) do
    PlaybackActivity
    |> Repo.get_by(rowid: data.rowid, server_id: data.server_id)
    |> case do
      nil -> %PlaybackActivity{}
      existing -> existing
    end
    |> PlaybackActivity.changeset(data)
    |> Repo.insert_or_update()
  end

  defp map_playback_data(data, server) do
    [
      rowid,
      date_created,
      jellyfin_user_id,
      item_id,
      item_type,
      item_name,
      play_method,
      client_name,
      device_name,
      play_duration
    ] = data

    user = get_or_create_user(server, jellyfin_user_id)

    %{
      rowid: parse_integer(rowid),
      server_id: server.id,
      date_created: parse_datetime(date_created),
      user_id: user.id,
      item_id: item_id,
      item_type: item_type,
      item_name: item_name,
      play_method: play_method,
      client_name: client_name,
      device_name: device_name,
      play_duration: parse_integer(play_duration),
      inserted_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second),
      updated_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
    }
  end

  defp get_or_create_user(server, jellyfin_user_id) do
    Logger.info(
      "Getting or creating user with Jellyfin ID #{jellyfin_user_id} for server #{server.id}"
    )

    case Repo.get_by(User, name: jellyfin_user_id, server_id: server.id) do
      nil ->
        Logger.info("User not found. Creating new user.")
        {:ok, user} = create_user(server, jellyfin_user_id)
        user

      user ->
        Logger.info("User found: #{user.name}")
        user
    end
  end

  defp create_user(server, jellyfin_user_id) do
    Logger.info("Creating new user with Jellyfin ID #{jellyfin_user_id} for server #{server.id}")

    case JellyfinClient.get_user(server, jellyfin_user_id) do
      {:ok, user_data} ->
        Logger.info("Received user data from Jellyfin: #{inspect(user_data)}")

        result =
          %User{}
          |> User.changeset(%{
            jellyfin_id: jellyfin_user_id,
            name: user_data["Name"],
            server_id: server.id
          })
          |> Repo.insert()

        case result do
          {:ok, user} ->
            Logger.info("Successfully created user: #{user.name}")
            {:ok, user}

          {:error, changeset} ->
            Logger.error("Failed to create user: #{inspect(changeset.errors)}")
            {:error, changeset.errors}
        end

      {:error, reason} ->
        Logger.error("Failed to fetch user data from Jellyfin: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp parse_integer(string) do
    case Integer.parse(string) do
      {int, _} ->
        int

      :error ->
        Logger.warning("Failed to parse integer: #{string}")
        0
    end
  end

  defp update_server_last_synced_id_if_needed(server, mapped_data) do
    max_rowid = Enum.map(mapped_data, & &1.rowid) |> Enum.max(fn -> 0 end)

    if max_rowid > 0 and max_rowid > server.last_synced_playback_id do
      update_server_last_synced_id(server, max_rowid)
    end
  end

  defp parse_datetime(datetime_string) do
    case NaiveDateTime.from_iso8601(datetime_string) do
      {:ok, datetime} ->
        NaiveDateTime.truncate(datetime, :second)

      {:error, _} ->
        Logger.warning("Failed to parse datetime: #{datetime_string}")
        nil
    end
  end

  defp update_server_last_synced_id(server, max_rowid) do
    server
    |> Server.changeset(%{last_synced_playback_id: max_rowid})
    |> Repo.update()
  end

  defp get_library_by_jellyfin_id(jellyfin_library_id, server_id) do
    case Repo.get_by(Library, jellyfin_id: jellyfin_library_id, server_id: server_id) do
      nil -> {:error, :library_not_found}
      library -> {:ok, library}
    end
  end

  defp map_jellyfin_item(jellyfin_item, library_id, server_id) do
    %{
      jellyfin_id: jellyfin_item["Id"],
      name: jellyfin_item["Name"],
      type: jellyfin_item["Type"],
      library_id: library_id,
      server_id: server_id,
      inserted_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second),
      updated_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
    }
  end

  defp map_jellyfin_user(user_data, server_id) do
    %{
      jellyfin_id: user_data["Id"],
      name: user_data["Name"],
      server_id: server_id,
      inserted_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second),
      updated_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
    }
  end

  defp map_jellyfin_library(jellyfin_library, server_id) do
    %{
      jellyfin_id: jellyfin_library["Id"],
      name: jellyfin_library["Name"],
      type: jellyfin_library["CollectionType"],
      server_id: server_id,
      inserted_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second),
      updated_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
    }
  end
end
