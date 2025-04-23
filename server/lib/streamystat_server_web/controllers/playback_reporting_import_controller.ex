defmodule StreamystatServerWeb.PlaybackReportingImportController do
  use StreamystatServerWeb, :controller
  require Logger
  alias StreamystatServer.Workers.PlaybackReportingImporter

  def import(conn, %{"server_id" => server_id} = params) do
    Logger.info("Playback Reporting import request received for server: #{server_id}")

    case get_import_data(conn, params) do
      {:ok, import_data, file_type} ->
        # Start the import process
        PlaybackReportingImporter.import_data(server_id, import_data, file_type)

        conn
        |> put_status(:accepted)
        |> render(:import,
          message: "Playback Reporting import started successfully",
          status: "processing"
        )

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: reason})
    end
  end

  # Extract data from either uploaded file or request body
  defp get_import_data(conn, params) do
    cond do
      # Check if there's a file upload
      upload = params["file"] ->
        handle_file_upload(upload)

      # Check if there's a json_data parameter
      json_data = params["json_data"] ->
        {:ok, json_data, "json"}

      # Check if there's a raw JSON body
      true ->
        case read_body(conn) do
          {:ok, body, _} when body != "" ->
            case Jason.decode(body) do
              # Verify it's valid JSON
              {:ok, _} -> {:ok, body, "json"}
              {:error, _} -> {:error, "Invalid JSON format in request body"}
            end

          _ ->
            {:error, "No import data provided"}
        end
    end
  end

  defp handle_file_upload(%Plug.Upload{path: path, content_type: content_type, filename: filename}) do
    cond do
      # Handle JSON files
      String.contains?(content_type, "json") || String.ends_with?(filename, ".json") ->
        case File.read(path) do
          {:ok, content} ->
            # Just verify it's valid JSON, but keep the original string
            case Jason.decode(content) do
              {:ok, _} -> {:ok, content, "json"}
              {:error, _} -> {:error, "Invalid JSON content in uploaded file"}
            end

          {:error, reason} ->
            {:error, "Failed to read uploaded file: #{inspect(reason)}"}
        end

      # Handle TSV files
      String.contains?(content_type, "tab-separated-values") ||
        String.ends_with?(filename, ".tsv") ||
          String.ends_with?(filename, ".txt") ->
        case File.read(path) do
          {:ok, content} -> {:ok, content, "tsv"}
          {:error, reason} -> {:error, "Failed to read uploaded file: #{inspect(reason)}"}
        end

      true ->
        {:error, "File must be JSON or TSV format"}
    end
  end

  defp handle_file_upload(_), do: {:error, "Invalid file upload"}
end
