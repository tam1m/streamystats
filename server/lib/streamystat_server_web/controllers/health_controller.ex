defmodule StreamystatServerWeb.HealthController do
  use StreamystatServerWeb, :controller

  def check(conn, _params) do
    conn
    |> put_status(:ok)
    |> json(%{status: "ok"})
  end
end
