defmodule StreamystatServer.Repo.Migrations.AddPgvectorExtension do
  use Ecto.Migration

  def change do
    execute("CREATE EXTENSION IF NOT EXISTS vectors")
  end
end
