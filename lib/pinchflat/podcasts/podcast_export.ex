defmodule Pinchflat.Podcasts.PodcastExport do
  @moduledoc """
  Publishes podcast feeds by serving the podcast library **in place**: podcast
  sources download straight into `<podcast_directory>/<slug>/`, and this module
  only writes the small generated artifacts alongside the media — `feed.xml`,
  `cover.<ext>`, and a root `opml.xml`. A dumb static file server points at
  `podcast_directory` and hosts everything with no reach back into Tubeless.

      <podcast_directory>/
        opml.xml                    # all published sources
        lex-fridman/
          feed.xml                  # generated
          cover.jpg                 # generated (small copy of the source cover)
          2026-07-19 dQw4w9WgXcQ.mp3 # the download itself — never duplicated
          2026-07-19 dQw4w9WgXcQ.jpg # episode thumbnail (if downloaded)

  Media files are owned by the download/retention system (they live here because
  that's where they were downloaded), so this module never copies, moves, or
  prunes them — only the generated feed/cover/opml files it owns.
  """

  use Pinchflat.Sources.SourcesQuery

  alias Pinchflat.Repo
  alias Pinchflat.Settings
  alias Pinchflat.Sources.Source
  alias Pinchflat.Profiles.MediaProfile
  alias Pinchflat.Podcasts.PodcastHelpers
  alias Pinchflat.Podcasts.RssFeedBuilder
  alias Pinchflat.Podcasts.OpmlFeedBuilder
  alias Pinchflat.Podcasts.StaticFeedLinks
  alias Pinchflat.Utils.StringUtils
  alias Pinchflat.Utils.FilesystemUtils

  @media_items_per_feed 2_000

  @doc """
  Determines whether a source is published as a podcast: driven entirely by its
  media profile's podcast mode.

  Returns boolean()
  """
  def enabled?(source) do
    source = Repo.preload(source, :media_profile)

    is_nil(source.marked_for_deletion_at) && MediaProfile.podcast?(source.media_profile)
  end

  @doc """
  Returns the configured public origin of the static file server, or nil
  if the user hasn't set one up (in which case feeds can't be built since
  they require absolute URLs).

  Returns binary() | nil
  """
  def url_base do
    Settings.get!(:podcast_url_base)
  end

  @doc """
  Returns the podcast library root: the servable directory podcasts live in.

  Returns binary()
  """
  def podcast_directory do
    Application.get_env(:pinchflat, :podcast_directory)
  end

  @doc """
  Returns the filename of the generated feed document.

  Returns binary()
  """
  def feed_filename, do: StaticFeedLinks.feed_filename()

  @doc """
  Whether the generated `feed.xml` actually exists on disk for a source. Export
  is debounced (and can fail), so this is the source of truth for "is the feed
  really published?" rather than merely "is the source configured to publish?".

  Returns boolean()
  """
  def feed_generated?(%Source{slug: slug}) when is_binary(slug) do
    File.exists?(Path.join(source_export_directory(%Source{slug: slug}), feed_filename()))
  end

  def feed_generated?(_source), do: false

  @doc """
  Returns all sources currently published as podcasts.

  Returns [%Source{}]
  """
  def export_enabled_sources do
    SourcesQuery.new()
    |> where([s], is_nil(s.marked_for_deletion_at))
    |> order_by(asc: :custom_name)
    |> preload(:media_profile)
    |> Repo.all()
    |> Enum.filter(&enabled?/1)
  end

  @doc """
  Writes the generated feed for a single source in place: `feed.xml` plus a
  `cover` image alongside the already-downloaded media. Does not touch media.

  Returns :ok
  """
  def export_source(source, url_base) do
    directory = source_export_directory(source)

    media_items =
      source
      |> PodcastHelpers.persisted_media_items_for(limit: @media_items_per_feed)
      |> Enum.filter(&under_podcast_directory?(&1.media_filepath))

    File.mkdir_p!(directory)
    write_cover_image(directory, source, media_items)

    feed_xml =
      RssFeedBuilder.build(source,
        url_base: url_base,
        link_module: StaticFeedLinks,
        media_items: media_items
      )

    write_atomically(Path.join(directory, StaticFeedLinks.feed_filename()), feed_xml)

    :ok
  end

  @doc """
  Removes the generated feed/cover files for a source (used when a source stops
  publishing or is deleted). Leaves the media files alone — those are managed by
  the download/retention system — and removes the directory only if it's now
  empty.

  Returns :ok
  """
  def prune_source(source) do
    remove_generated_feed_files(source_export_directory(source))

    :ok
  end

  @doc """
  Cleans up after a deleted source: removes its generated feed files and, when
  a URL base is configured, rewrites the OPML document without it.

  Returns :ok
  """
  def handle_source_deleted(source) do
    prune_source(source)

    case url_base() do
      nil -> :ok
      url_base -> write_opml(url_base)
    end
  end

  @doc """
  Writes the OPML document listing all published sources.

  Returns :ok
  """
  def write_opml(url_base) do
    xml = OpmlFeedBuilder.build(url_base, export_enabled_sources(), link_module: StaticFeedLinks)
    write_atomically(Path.join(podcast_directory(), "opml.xml"), xml)

    :ok
  end

  @doc """
  Full reconcile: regenerates every published source's feed, removes generated
  feed files for directories no longer backed by a published source, and
  rewrites the OPML document.

  Returns :ok | {:error, :no_url_base}
  """
  def sweep do
    case url_base() do
      nil ->
        {:error, :no_url_base}

      url_base ->
        enabled_sources = export_enabled_sources()

        Enum.each(enabled_sources, &export_source(&1, url_base))
        prune_orphaned_feeds(Enum.map(enabled_sources, & &1.slug))
        write_opml(url_base)
    end
  end

  defp source_export_directory(%Source{slug: slug}) do
    Path.join(podcast_directory(), slug)
  end

  # Only media that actually lives under the podcast library can be served by the
  # static file server. Media downloaded before the source became a podcast (or
  # under a non-podcast profile) still lives under the media library, and
  # `StaticFeedLinks` would build an unreachable enclosure URL from it — so it's
  # excluded until it's re-downloaded into the podcast library.
  defp under_podcast_directory?(filepath) do
    root = Path.expand(podcast_directory())
    expanded = Path.expand(filepath)

    expanded == root || String.starts_with?(expanded, root <> "/")
  end

  # Cover art is tiny (unlike media), so a copy here is fine. Written atomically
  # so a podcast client never fetches a half-written image
  defp write_cover_image(directory, source, media_items) do
    case PodcastHelpers.select_cover_image(source, media_items) do
      {:error, _} ->
        :ok

      {:ok, filepath} ->
        dest = Path.join(directory, "cover#{Path.extname(filepath)}")
        copy_atomically(filepath, dest)
        remove_stale_covers(directory, dest)
    end
  end

  # If the source's cover changed extension (jpg -> png), drop the old one so
  # the directory doesn't accumulate covers the feed no longer references
  defp remove_stale_covers(directory, current_cover) do
    directory
    |> Path.join("cover.*")
    |> Path.wildcard()
    |> Enum.reject(&(&1 == current_cover || String.ends_with?(&1, ".tmp")))
    |> Enum.each(&File.rm/1)

    :ok
  end

  # Removes the files this module generates (feed + cover) and the directory if
  # it's now empty. Never removes media
  defp remove_generated_feed_files(directory) do
    ([Path.join(directory, StaticFeedLinks.feed_filename())] ++ Path.wildcard(Path.join(directory, "cover.*")))
    |> Enum.each(&File.rm/1)

    # No-op unless the directory is now empty (media may still live here)
    File.rmdir(directory)

    :ok
  end

  defp prune_orphaned_feeds(enabled_slugs) do
    case File.ls(podcast_directory()) do
      {:ok, entries} ->
        entries
        |> Enum.reject(&(&1 in enabled_slugs))
        |> Enum.map(&Path.join(podcast_directory(), &1))
        # Only touch directories we actually generated a feed into, so unrelated
        # files/folders under the podcast root are never disturbed
        |> Enum.filter(&File.exists?(Path.join(&1, StaticFeedLinks.feed_filename())))
        |> Enum.each(&remove_generated_feed_files/1)

      {:error, _} ->
        :ok
    end
  end

  defp copy_atomically(source_path, dest_path) do
    File.mkdir_p!(Path.dirname(dest_path))
    tmp_path = "#{dest_path}.#{StringUtils.random_string(8)}.tmp"

    try do
      File.cp!(source_path, tmp_path)
      File.rename!(tmp_path, dest_path)
    after
      File.rm(tmp_path)
    end
  end

  # Feeds are re-read by podcast apps at any time, so never leave a half-written
  # document visible — write to a tempfile and rename over. The tempfile name is
  # randomized so concurrent writers (eg: a per-source export and a synchronous
  # source deletion both rewriting opml.xml) can't rename each other's tempfile
  # out from under them and raise :enoent
  defp write_atomically(filepath, contents) do
    tmp_filepath = "#{filepath}.#{StringUtils.random_string(8)}.tmp"

    FilesystemUtils.write_p!(tmp_filepath, contents)
    File.rename!(tmp_filepath, filepath)
  end
end
