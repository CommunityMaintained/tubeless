defmodule Pinchflat.Podcasts.StaticFeedLinks do
  @moduledoc """
  Builds feed URLs for the served-in-place podcast library: plain files under a
  dumb file server (`podcast_url_base` setting), with no reach back into
  Tubeless.

  Media and thumbnail URLs are the file's real path relative to the podcast
  library (URL-encoded per segment), because the download already lives there —
  nothing is copied or renamed. The generated `feed.xml` and `cover` live in the
  source's slug directory. Slugs are stable across renames, so subscriptions
  survive title edits.

  Implements the same informal contract as `Pinchflat.Podcasts.DynamicFeedLinks`:
  `self_url/2`, `enclosure_url/3`, `feed_image_url/3`, `episode_image_url/3`,
  and `opml_feed_url/2`.
  """

  alias Pinchflat.Podcasts.PodcastHelpers

  @doc """
  Returns the name of the directory a source's feed lives in, relative to the
  podcast library (the source's stable slug).

  Returns binary()
  """
  def source_directory_name(source), do: source.slug

  @doc """
  Returns the filename of a source's feed document.

  Returns binary()
  """
  def feed_filename, do: "feed.xml"

  @doc """
  Returns the feed's own URL (used for the `atom:link rel="self"` element).

  Returns binary()
  """
  def self_url(url_base, source) do
    join(url_base, "#{source_directory_name(source)}/#{feed_filename()}")
  end

  @doc """
  Returns the URL of a media item's enclosure: its real path under the podcast
  library, URL-encoded.

  Returns binary()
  """
  def enclosure_url(url_base, _source, media_item) do
    join(url_base, relative_url_path(media_item.media_filepath))
  end

  @doc """
  Returns the URL of the feed's cover image or "" if no suitable image exists.

  Returns binary()
  """
  def feed_image_url(url_base, source, media_items) do
    case PodcastHelpers.select_cover_image(source, media_items) do
      {:error, _} -> ""
      {:ok, filepath} -> join(url_base, "#{source_directory_name(source)}/cover#{Path.extname(filepath)}")
    end
  end

  @doc """
  Returns the URL of a media item's episode image or nil if it has none on disk.

  Returns binary() | nil
  """
  def episode_image_url(url_base, _source, media_item) do
    if media_item.thumbnail_filepath && File.exists?(media_item.thumbnail_filepath) do
      join(url_base, relative_url_path(media_item.thumbnail_filepath))
    else
      nil
    end
  end

  @doc """
  Returns the URL a source's feed is reachable at, for use in OPML documents.

  Returns binary()
  """
  def opml_feed_url(url_base, source) do
    self_url(url_base, source)
  end

  # The file's path relative to the podcast library, with each segment
  # URL-encoded (spaces, brackets, etc.) so the resulting URL is valid
  defp relative_url_path(filepath) do
    filepath
    |> Path.relative_to(podcast_directory())
    |> Path.split()
    |> Enum.map_join("/", &URI.encode(&1, fn char -> URI.char_unreserved?(char) end))
  end

  defp join(url_base, relative_path) do
    Path.join(url_base, relative_path)
  end

  defp podcast_directory do
    Application.get_env(:pinchflat, :podcast_directory)
  end
end
