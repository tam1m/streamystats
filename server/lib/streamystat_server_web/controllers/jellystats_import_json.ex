defmodule StreamystatServerWeb.JellystatsImportJSON do
  @moduledoc """
  JSON view for JellystatsImportController responses.
  """

  def import(%{message: message, status: status}) do
    %{
      message: message,
      status: status
    }
  end
end
