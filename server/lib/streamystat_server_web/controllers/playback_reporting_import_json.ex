defmodule StreamystatServerWeb.PlaybackReportingImportJSON do
  @moduledoc """
  JSON view for PlaybackReportingImportController responses.
  """

  def import(%{message: message, status: status}) do
    %{
      message: message,
      status: status
    }
  end
end
