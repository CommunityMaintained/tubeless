defmodule Pinchflat.Podcasts.DynamicFeedLinks do
  @moduledoc """
  Builds feed URLs that point at Tubeless' own dynamic podcast endpoints
  (`/sources/:uuid/feed` and friends). This is the original behaviour and is
  used by the feed endpoints served directly by the app.

  Implements the same informal contract as `Pinchflat.Podcasts.StaticFeedLinks`:
  `self_url/2`, `enclosure_url/3`, `feed_image_url/3`, `episode_image_url/3`,
  and `opml_feed_url/2`.
  """

  alias Pinchflat.Podcasts.PodcastHelpers
  alias PinchflatWeb.Router.Helpers, as: Routes

  @doc """
  Returns the feed's own URL (used for the `atom:link rel="self"` element).

  Returns binary()
  """
  def self_url(url_base, source) do
    Path.join(url_base, "#{podcast_route(:rss_feed, source.uuid)}.xml")
  end

  @doc """
  Returns the streaming URL for a media item's enclosure.

  Returns binary()
  """
  def enclosure_url(url_base, _source, media_item) do
    extension = Path.extname(media_item.media_filepath)

    Path.join(url_base, "#{media_route(:stream, media_item.uuid)}#{extension}")
  end

  @doc """
  Returns the URL of the feed's cover image or "" if no suitable image exists.

  Returns binary()
  """
  def feed_image_url(url_base, source, media_items) do
    case PodcastHelpers.select_cover_image(source, media_items) do
      {:error, _} ->
        ""

      {:ok, filepath} ->
        extension = Path.extname(filepath)
        Path.join(url_base, "#{podcast_route(:feed_image, source.uuid)}#{extension}")
    end
  end

  @doc """
  Returns the URL of a media item's episode image or nil if it has none on disk.

  Returns binary() | nil
  """
  def episode_image_url(url_base, _source, media_item) do
    if media_item.thumbnail_filepath && File.exists?(media_item.thumbnail_filepath) do
      extension = Path.extname(media_item.thumbnail_filepath)

      Path.join(url_base, "#{podcast_route(:episode_image, media_item.uuid)}#{extension}")
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

  defp podcast_route(action, params) do
    Routes.podcast_path(PinchflatWeb.Endpoint, action, params)
  end

  defp media_route(action, params) do
    Routes.media_item_path(PinchflatWeb.Endpoint, action, params)
  end
end
