defmodule StreamystatServerWeb.AuthJSON do
  def login(%{access_token: access_token, user: user}) do
    %{access_token: access_token, user: user}
  end

  @spec error(%{:message => any(), optional(any()) => any()}) :: %{error: any()}
  def error(%{message: message}) do
    %{error: message}
  end
end
