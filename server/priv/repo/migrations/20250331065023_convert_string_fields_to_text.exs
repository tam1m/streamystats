defmodule StreamystatServer.Repo.Migrations.ConvertStringFieldsToText do
  use Ecto.Migration

  def up do
    # Library table
    alter table(:jellyfin_libraries) do
      modify(:jellyfin_id, :text)
      modify(:name, :text)
      modify(:type, :string)
    end

    # Item table
    alter table(:jellyfin_items) do
      modify(:jellyfin_id, :text)
      modify(:name, :text)
      modify(:type, :string)
      modify(:original_title, :text)
      modify(:etag, :string)
      modify(:container, :string)
      modify(:sort_name, :text)
      modify(:path, :text)
      modify(:official_rating, :string)
      modify(:overview, :text)
      modify(:parent_id, :string)
      modify(:media_type, :string)
      modify(:series_name, :text)
      modify(:series_id, :string)
      modify(:season_id, :string)
      modify(:series_primary_image_tag, :string)
      modify(:season_name, :text)
      modify(:series_studio, :text)
    end

    # User table
    alter table(:jellyfin_users) do
      modify(:jellyfin_id, :text)
      modify(:name, :text)
      modify(:authentication_provider_id, :string)
      modify(:password_reset_provider_id, :string)
      modify(:sync_play_access, :string)
    end

    # Activity table
    alter table(:activities) do
      modify(:name, :text)
      modify(:short_overview, :text)
      modify(:type, :string)
      modify(:severity, :string)
    end

    # Playback Session table
    alter table(:playback_sessions) do
      modify(:user_jellyfin_id, :string)
      modify(:device_id, :text)
      modify(:device_name, :text)
      modify(:client_name, :text)
      modify(:item_jellyfin_id, :string)
      modify(:item_name, :text)
      modify(:series_jellyfin_id, :string)
      modify(:series_name, :text)
      modify(:season_jellyfin_id, :string)
      modify(:play_method, :string)
    end
  end

  def down do
    # Library table
    alter table(:jellyfin_libraries) do
      modify(:jellyfin_id, :string)
      modify(:name, :string)
      modify(:type, :string)
    end

    # Item table
    alter table(:jellyfin_items) do
      modify(:jellyfin_id, :string)
      modify(:name, :string)
      modify(:type, :string)
      modify(:original_title, :string)
      modify(:etag, :string)
      modify(:container, :string)
      modify(:sort_name, :string)
      modify(:path, :string)
      modify(:official_rating, :string)
      modify(:overview, :string)
      modify(:parent_id, :string)
      modify(:media_type, :string)
      modify(:series_name, :string)
      modify(:series_id, :string)
      modify(:season_id, :string)
      modify(:series_primary_image_tag, :string)
      modify(:season_name, :string)
      modify(:series_studio, :string)
    end

    # User table
    alter table(:jellyfin_users) do
      modify(:jellyfin_id, :string)
      modify(:name, :string)
      modify(:authentication_provider_id, :string)
      modify(:password_reset_provider_id, :string)
      modify(:sync_play_access, :string)
    end

    # Activity table
    alter table(:activities) do
      modify(:name, :string)
      modify(:short_overview, :string)
      modify(:type, :string)
      modify(:severity, :string)
    end

    # Playback Session table
    alter table(:playback_sessions) do
      modify(:user_jellyfin_id, :string)
      modify(:device_id, :string)
      modify(:device_name, :string)
      modify(:client_name, :string)
      modify(:item_jellyfin_id, :string)
      modify(:item_name, :string)
      modify(:series_jellyfin_id, :string)
      modify(:series_name, :string)
      modify(:season_jellyfin_id, :string)
      modify(:play_method, :string)
    end
  end
end
