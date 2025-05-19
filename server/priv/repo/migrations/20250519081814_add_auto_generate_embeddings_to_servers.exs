defmodule StreamystatServer.Repo.Migrations.AddAutoGenerateEmbeddingsToServers do
  use Ecto.Migration

  def change do
    alter table(:servers) do
      add :auto_generate_embeddings, :boolean, default: false, null: false
    end
  end
end
