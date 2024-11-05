# lib/streamystat_server/jellyfin/item.ex
defmodule StreamystatServer.Jellyfin.Item do
  use Ecto.Schema
  import Ecto.Changeset
  alias StreamystatServer.Servers.Server
  alias StreamystatServer.Jellyfin.Library

  schema "jellyfin_items" do
    field(:jellyfin_id, :string)
    field(:name, :string)
    field(:type, :string)
    field(:original_title, :string)
    field(:etag, :string)
    field(:date_created, :utc_datetime)
    field(:container, :string)
    field(:sort_name, :string)
    field(:premiere_date, :utc_datetime)
    field(:external_urls, {:array, :map})
    field(:path, :string)
    field(:official_rating, :string)
    field(:overview, :string)
    field(:genres, {:array, :string})
    field(:community_rating, :float)
    field(:runtime_ticks, :integer)
    field(:production_year, :integer)
    field(:is_folder, :boolean)
    field(:parent_id, :string)
    field(:media_type, :string)
    field(:width, :integer)
    field(:height, :integer)
    field(:series_name, :string)
    field(:series_id, :string)
    field(:season_id, :string)
    field(:series_primary_image_tag, :string)
    field(:season_name, :string)
    field(:series_studio, :string)
    belongs_to(:library, Library)
    belongs_to(:server, Server)

    timestamps()
  end

  def changeset(item, attrs) do
    item
    |> cast(attrs, [
      :jellyfin_id,
      :name,
      :type,
      :library_id,
      :server_id,
      :original_title,
      :etag,
      :date_created,
      :container,
      :sort_name,
      :premiere_date,
      :external_urls,
      :path,
      :official_rating,
      :overview,
      :genres,
      :community_rating,
      :runtime_ticks,
      :production_year,
      :is_folder,
      :parent_id,
      :media_type,
      :width,
      :height,
      :series_name,
      :series_id,
      :season_id,
      :series_primary_image_tag,
      :season_name,
      :series_studio
    ])
    |> validate_required([:jellyfin_id, :name, :type, :library_id, :server_id])
    |> unique_constraint([:jellyfin_id, :library_id])
    |> foreign_key_constraint(:library_id)
    |> foreign_key_constraint(:server_id)
  end
end
