defmodule StreamystatServerWeb.TautulliImportController do
  use StreamystatServerWeb, :controller
  require Logger
  alias StreamystatServer.Workers.TautulliImporter

  def import(conn, params) do
    Logger.info("Tautulli import request received: #{inspect(params, pretty: true)}")

    with {:ok, server_id} <- extract_param(params, "server_id"),
         {:ok, tautulli_url} <- extract_param(params, "tautulli_url"),
         {:ok, api_key} <- extract_param(params, "api_key"),
         {:ok, mappings} <- parse_mappings(params["mappings"]) do

      Logger.info("Starting Tautulli import for server #{server_id}")
      Logger.info("Using Tautulli URL: #{tautulli_url}")
      Logger.info("Mappings configured: #{inspect(mappings, pretty: true)}")

      # Start import process
      TautulliImporter.import_data(server_id, tautulli_url, api_key, mappings)

      conn
      |> put_status(:accepted)
      |> json(%{
        message: "Tautulli import started successfully",
        status: "processing"
      })
    else
      {:error, message} ->
        Logger.error("Tautulli import request failed: #{message}")

        conn
        |> put_status(:bad_request)
        |> json(%{error: message})
    end
  end

  # Helper functions
  defp extract_param(params, key) do
    case Map.fetch(params, key) do
      {:ok, value} when is_binary(value) and value != "" ->
        {:ok, value}
      _ ->
        {:error, "Missing or invalid parameter: #{key}"}
    end
  end

  defp parse_mappings(nil), do: {:ok, %{}}

  defp parse_mappings(mappings) when is_map(mappings) do
    library_mappings = Map.get(mappings, "libraryMappings", [])
    user_mappings = Map.get(mappings, "userMappings", [])

    Logger.info("Parsed library mappings: #{inspect(library_mappings, pretty: true)}")
    Logger.info("Parsed user mappings: #{inspect(user_mappings, pretty: true)}")

    {:ok, %{
      library_mappings: library_mappings,
      user_mappings: user_mappings
    }}
  end

  defp parse_mappings(mappings) when is_binary(mappings) do
    case Jason.decode(mappings) do
      {:ok, decoded} ->
        parse_mappings(decoded)
      {:error, _} ->
        Logger.error("Failed to parse mappings JSON: #{mappings}")
        {:error, "Invalid JSON format for mappings"}
    end
  end

  defp parse_mappings(_), do: {:error, "Mappings must be a JSON object"}
end
