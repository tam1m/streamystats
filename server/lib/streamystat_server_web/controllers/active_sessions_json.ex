defmodule StreamystatServerWeb.ActiveSessionsJSON do
  @doc """
  Renders a list of active sessions.
  """
  def index(%{active_sessions: active_sessions}) do
    %{data: for(session <- active_sessions, do: render_session(session))}
  end

  defp render_session(session) do
    %{
      session_key: session.session_key,
      user: session.user,
      item: session.item,
      client: session.client,
      device_name: session.device_name,
      device_id: session.device_id,
      position_ticks: session.position_ticks,
      formatted_position: session.formatted_position,
      runtime_ticks: session.runtime_ticks,
      formatted_runtime: session.formatted_runtime,
      progress_percent: session.progress_percent,
      playback_duration: session.playback_duration,
      last_activity_date: format_datetime(session.last_activity_date),
      is_paused: session.is_paused,
      play_method: session.play_method
    }
  end

  defp format_datetime(nil), do: nil
  defp format_datetime(datetime) do
    datetime
    |> DateTime.truncate(:second)
    |> DateTime.to_iso8601()
  end
end
