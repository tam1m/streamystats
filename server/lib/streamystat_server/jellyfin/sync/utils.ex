defmodule StreamystatServer.Jellyfin.Sync.Utils do
  @moduledoc """
  Common utility functions for Jellyfin sync operations.
  """

  require Logger
  alias StreamystatServer.Repo
  alias StreamystatServer.Jellyfin.Models.Library

  @doc """
  Sanitizes a string by removing null bytes and control characters.
  Returns nil for nil input.
  """
  def sanitize_string(nil), do: nil

  def sanitize_string(str) when is_binary(str) do
    str
    |> String.replace(<<0>>, "")
    |> String.replace(~r/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/, "")
  end

  def sanitize_string(other), do: other

  @doc """
  Parses a datetime string in ISO 8601 format to a UTC DateTime.
  Returns nil for nil or empty input.
  """
  def parse_datetime_to_utc(nil), do: nil
  def parse_datetime_to_utc(""), do: nil

  def parse_datetime_to_utc(datetime_string) when is_binary(datetime_string) do
    case DateTime.from_iso8601(datetime_string) do
      {:ok, datetime, _offset} ->
        DateTime.truncate(datetime, :second)

      {:error, _} ->
        case NaiveDateTime.from_iso8601(datetime_string) do
          {:ok, naive_datetime} ->
            naive_datetime
            |> DateTime.from_naive!("Etc/UTC")
            |> DateTime.truncate(:second)

          {:error, _} ->
            Logger.warning("Failed to parse datetime: #{datetime_string}")
            nil
        end
    end
  end

  def parse_datetime_to_utc(_), do: nil

  @doc """
  Safely parses a value to float.
  Returns nil for nil input or parsing errors.
  """
  def parse_float(nil), do: nil

  def parse_float(string) when is_binary(string) do
    case Float.parse(string) do
      {float, _} -> float
      :error -> nil
    end
  end

  def parse_float(number) when is_integer(number), do: number / 1
  def parse_float(number) when is_float(number), do: number
  def parse_float(_), do: nil

  @doc """
  Gets a library by its Jellyfin ID and server ID.
  Returns {:ok, library} or {:error, :library_not_found}.
  """
  def get_library_by_jellyfin_id(jellyfin_library_id, server_id) do
    case Repo.get_by(Library, jellyfin_id: jellyfin_library_id, server_id: server_id) do
      nil -> {:error, :library_not_found}
      library -> {:ok, library}
    end
  end

  @doc """
  Gets all libraries for a server.
  """
  def get_libraries_by_server(server_id) do
    import Ecto.Query
    Repo.all(from(l in Library, where: l.server_id == ^server_id))
  end

  @doc """
  Determines if fields have changed between two maps or structs.
  """
  def fields_changed?(existing_item, new_item, fields) do
    Enum.any?(fields, fn field ->
      Map.get(existing_item, field) != Map.get(new_item, field)
    end)
  end

  @doc """
  Determines if image-related fields have changed between two maps or structs.
  This is a more specific check for image changes that also considers the etag.
  """
  def image_fields_changed?(existing_item, new_item) do
    image_fields = [
      :primary_image_tag,
      :backdrop_image_tags,
      :primary_image_thumb_tag,
      :primary_image_logo_tag,
      :image_blur_hashes,
      :parent_backdrop_image_tags,
      :parent_thumb_image_tag,
      :series_primary_image_tag
    ]

    # First check if etag has changed (indicates any change in Jellyfin)
    etag_changed = Map.get(existing_item, :etag) != Map.get(new_item, :etag)

    # Then check specific image fields
    image_fields_changed = Enum.any?(image_fields, fn field ->
      existing_value = Map.get(existing_item, field)
      new_value = Map.get(new_item, field)

      # Handle array fields differently
      if is_list(existing_value) and is_list(new_value) do
        existing_value != new_value
      else
        existing_value != new_value
      end
    end)

    etag_changed or image_fields_changed
  end
end
