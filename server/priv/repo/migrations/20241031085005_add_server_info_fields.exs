defmodule StreamystatServer.Repo.Migrations.AddServerInfoFields do
  use Ecto.Migration

  def change do
    alter table(:servers) do
      add(:local_address, :string)
      add(:server_name, :string)
      add(:version, :string)
      add(:product_name, :string)
      add(:operating_system, :string)
      add(:jellyfin_id, :string)
      add(:startup_wizard_completed, :boolean, default: false)
    end
  end
end
