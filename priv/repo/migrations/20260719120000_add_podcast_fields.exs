defmodule Pinchflat.Repo.Migrations.AddPodcastFields do
  use Ecto.Migration

  def change do
    alter table(:media_profiles) do
      # A profile with this enabled publishes its sources as podcasts. Whether
      # the podcast is audio or video follows the profile's preferred_resolution
      add :podcast_enabled, :boolean, default: false, null: false
    end

    alter table(:sources) do
      # Stable, human-readable folder/URL name for the source's podcast. Derived
      # from custom_name on insert and NOT changed on rename, so subscriptions
      # survive title edits
      add :slug, :string, null: true
    end

    alter table(:settings) do
      add :podcast_url_base, :string, null: true
    end

    # SQLite treats NULLs as distinct, so non-podcast sources (null slug) don't collide
    create unique_index(:sources, [:slug])
  end
end
