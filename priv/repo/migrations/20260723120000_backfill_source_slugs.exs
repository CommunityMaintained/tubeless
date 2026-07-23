defmodule Pinchflat.Repo.Migrations.BackfillSourceSlugs do
  use Ecto.Migration

  import Ecto.Query

  alias Pinchflat.Repo
  alias Pinchflat.Utils.StringUtils

  # The original podcast-fields migration added `sources.slug` as nullable and only
  # NEW/updated sources get one assigned (via `Sources.maybe_assign_slug`). Sources
  # that existed before this feature are left with NULL slugs, which then flow into
  # the output-path template parser as `nil` and crash EVERY download/index path
  # build (podcast or not). Backfill a stable, unique, readable slug for anyone
  # still missing one. Idempotent: fresh installs have no NULL-slug rows, so this
  # no-ops there.
  def up do
    existing_slugs =
      from(s in "sources", where: not is_nil(s.slug), select: s.slug)
      |> Repo.all()
      |> MapSet.new()

    sources_missing_slug =
      from(s in "sources", where: is_nil(s.slug), select: {s.id, s.custom_name})
      |> Repo.all()

    Enum.reduce(sources_missing_slug, existing_slugs, fn {id, custom_name}, taken ->
      slug = unique_slug(custom_name, taken)

      from(s in "sources", where: s.id == ^id)
      |> Repo.update_all(set: [slug: slug])

      MapSet.put(taken, slug)
    end)
  end

  def down, do: :ok

  defp unique_slug(custom_name, taken) do
    base =
      case StringUtils.to_slug(custom_name || "") do
        "" -> "podcast"
        slug -> slug
      end

    ensure_unique(base, base, 2, taken)
  end

  defp ensure_unique(candidate, base, next_suffix, taken) do
    if MapSet.member?(taken, candidate) do
      ensure_unique("#{base}-#{next_suffix}", base, next_suffix + 1, taken)
    else
      candidate
    end
  end
end
