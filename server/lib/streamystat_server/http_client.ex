defmodule StreamystatServer.HttpClient do
  def post(url, body, headers) do
    HTTPoison.post(url, body, headers)
  end

  def get(url, headers) do
    HTTPoison.get(url, headers)
  end
end
