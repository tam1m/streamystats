defmodule StreamystatServerWeb.ActiveSessionsController do
  use StreamystatServerWeb, :controller
  alias StreamystatServer.Contexts.ActiveSessions
  require Logger

  def index(conn, %{"server_id" => server_id}) do
    current_user = conn.assigns.current_user

    # If the user is an admin, get all sessions
    # If not, only get sessions for this user
    sessions =
      if is_admin?(current_user) do
        ActiveSessions.list_active_sessions(server_id)
      else
        ActiveSessions.list_user_active_sessions(server_id, current_user["Id"])
      end

    render(conn, :index, active_sessions: sessions)
  end

  defp is_admin?(user) do
    user["Policy"]["IsAdministrator"] == true
  end
end
