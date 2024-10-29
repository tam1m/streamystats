defmodule StreamystatServer.Repo.Migrations.AddUserReferenceToPlaybackActivities do
  use Ecto.Migration

  def change do
    alter table(:playback_activities) do
      remove(:user_id)
      add(:user_id, references(:jellyfin_users, on_delete: :nilify_all))
    end

    create(index(:playback_activities, [:user_id]))
  end
end
