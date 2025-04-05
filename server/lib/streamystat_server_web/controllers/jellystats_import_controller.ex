defmodule StreamystatServerWeb.JellystatsImportController do
  use StreamystatServerWeb, :controller
  require Logger
  alias StreamystatServer.Workers.JellystatsImporter

  def import(conn, %{"server_id" => server_id} = params) do
    Logger.info("Jellystats import request received for server: #{server_id}")

    case get_import_data(conn, params) do
      {:ok, import_data} ->
        # Start the import process
        JellystatsImporter.import_data(server_id, import_data)

        conn
        |> put_status(:accepted)
        |> render(:import, message: "Jellystats import started successfully", status: "processing")

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
        {:ok, json_data}

      # Check if there's a raw JSON body
      true ->
        case read_body(conn) do
          {:ok, body, _} when body != "" ->
            case Jason.decode(body) do
              {:ok, _} -> {:ok, body} # Verify it's valid JSON
              {:error, _} -> {:error, "Invalid JSON format in request body"}
            end
          _ ->
            {:error, "No import data provided"}
        end
    end
  end

  defp handle_file_upload(%Plug.Upload{path: path, content_type: content_type}) do
    if String.contains?(content_type, "json") || String.ends_with?(path, ".json") do
      case File.read(path) do
        {:ok, content} ->
          # Just verify it's valid JSON, but keep the original string
          case Jason.decode(content) do
            {:ok, _} -> {:ok, content}
            {:error, _} -> {:error, "Invalid JSON content in uploaded file"}
          end
        {:error, reason} -> {:error, "Failed to read uploaded file: #{inspect(reason)}"}
      end
    else
      {:error, "File must be JSON format"}
    end
  end

  defp handle_file_upload(_), do: {:error, "Invalid file upload"}
end
