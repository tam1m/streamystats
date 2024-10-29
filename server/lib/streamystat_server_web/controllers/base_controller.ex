defmodule StreamystatServerWeb.BaseController do
  defmacro __using__(_) do
    quote do
      use StreamystatServerWeb, :controller
      action_fallback(StreamystatServerWeb.FallbackController)
    end
  end
end
