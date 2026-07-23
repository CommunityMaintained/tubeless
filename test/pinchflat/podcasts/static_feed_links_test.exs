defmodule Pinchflat.Podcasts.StaticFeedLinksTest do
  use Pinchflat.DataCase

  import Pinchflat.MediaFixtures
  import Pinchflat.SourcesFixtures

  alias Pinchflat.Podcasts.StaticFeedLinks
  alias Pinchflat.Utils.FilesystemUtils

  @url_base "http://pods.local"

  setup do
    source = source_fixture(%{slug: "lex-fridman"})

    on_exit(fn -> File.rm_rf!(podcast_directory()) end)

    {:ok, source: source}
  end

  describe "source_directory_name/1" do
    test "is the source's slug", %{source: source} do
      assert StaticFeedLinks.source_directory_name(source) == "lex-fridman"
    end
  end

  describe "self_url/2" do
    test "points at the feed under the slug folder", %{source: source} do
      assert StaticFeedLinks.self_url(@url_base, source) == "#{@url_base}/lex-fridman/feed.xml"
    end
  end

  describe "enclosure_url/3" do
    test "is the media file's real library-relative path, URL-encoded", %{source: source} do
      media = podcast_file(source, "2026-07-19 Cool Title [id].mp3")
      item = media_item_fixture(%{source_id: source.id, media_filepath: media})

      assert StaticFeedLinks.enclosure_url(@url_base, source, item) ==
               "#{@url_base}/lex-fridman/2026-07-19%20Cool%20Title%20%5Bid%5D.mp3"
    end
  end

  describe "episode_image_url/3" do
    test "is the thumbnail's real path when present on disk", %{source: source} do
      thumb = podcast_file(source, "episode.jpg")
      item = media_item_fixture(%{source_id: source.id, thumbnail_filepath: thumb})

      assert StaticFeedLinks.episode_image_url(@url_base, source, item) == "#{@url_base}/lex-fridman/episode.jpg"
    end

    test "is nil when the thumbnail is absent", %{source: source} do
      item = media_item_fixture(%{source_id: source.id, thumbnail_filepath: nil})

      assert StaticFeedLinks.episode_image_url(@url_base, source, item) == nil
    end
  end

  describe "feed_image_url/3" do
    test "is empty when no cover is available", %{source: source} do
      assert StaticFeedLinks.feed_image_url(@url_base, source, []) == ""
    end
  end

  describe "opml_feed_url/2" do
    test "matches the self URL", %{source: source} do
      assert StaticFeedLinks.opml_feed_url(@url_base, source) == StaticFeedLinks.self_url(@url_base, source)
    end
  end

  defp podcast_file(source, filename) do
    path = Path.join([podcast_directory(), source.slug, filename])
    FilesystemUtils.cp_p!(media_filepath_fixture(), path)
    path
  end

  defp podcast_directory, do: Application.get_env(:pinchflat, :podcast_directory)
end
