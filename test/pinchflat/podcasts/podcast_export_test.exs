defmodule Pinchflat.Podcasts.PodcastExportTest do
  use Pinchflat.DataCase

  import Pinchflat.MediaFixtures
  import Pinchflat.SourcesFixtures
  import Pinchflat.ProfilesFixtures

  alias Pinchflat.Settings
  alias Pinchflat.Podcasts.PodcastExport
  alias Pinchflat.Utils.FilesystemUtils

  @url_base "http://pods.local"

  setup do
    profile = media_profile_fixture(%{podcast_enabled: true})
    source = source_fixture(%{media_profile_id: profile.id, slug: "lex-fridman"})

    on_exit(fn -> File.rm_rf!(PodcastExport.podcast_directory()) end)

    {:ok, profile: profile, source: source}
  end

  describe "enabled?/1" do
    test "is true for a source whose profile publishes", %{source: source} do
      assert PodcastExport.enabled?(source)
    end

    test "is false for a source whose profile does not publish" do
      profile = media_profile_fixture(%{podcast_enabled: false})
      source = source_fixture(%{media_profile_id: profile.id})

      refute PodcastExport.enabled?(source)
    end

    test "is false for a source marked for deletion", %{source: source} do
      {:ok, source} =
        source
        |> Ecto.Changeset.change(%{marked_for_deletion_at: DateTime.utc_now() |> DateTime.truncate(:second)})
        |> Repo.update()

      refute PodcastExport.enabled?(source)
    end
  end

  describe "export_source/2" do
    test "writes a feed referencing the media in place (no copy)", %{source: source} do
      media_item = downloaded_episode(source, "Some Title [id].mp3")

      assert :ok = PodcastExport.export_source(source, @url_base)

      feed = File.read!(feed_path(source))
      # The enclosure points at the media's real library-relative path
      assert String.contains?(feed, "#{@url_base}/lex-fridman/Some%20Title%20%5Bid%5D.mp3")
      assert String.contains?(feed, "#{@url_base}/lex-fridman/feed.xml")

      # The media file was not duplicated anywhere
      assert Path.wildcard(Path.join([PodcastExport.podcast_directory(), "lex-fridman", "*.mp3"])) == [
               media_item.media_filepath
             ]
    end

    test "writes a cover image into the slug folder" do
      profile = media_profile_fixture(%{podcast_enabled: true})
      source = source_with_metadata_attachments(%{media_profile_id: profile.id, slug: "with-cover"})
      downloaded_episode(source, "Title [id].mp3")

      assert :ok = PodcastExport.export_source(source, @url_base)

      assert [_] = Path.wildcard(Path.join([PodcastExport.podcast_directory(), "with-cover", "cover.*"]))
    end

    test "excludes items whose media file is missing", %{source: source} do
      present = downloaded_episode(source, "Present [id].mp3")
      media_item_fixture(%{source_id: source.id, media_filepath: "/nonexistent/media.mp3"})

      assert :ok = PodcastExport.export_source(source, @url_base)

      feed = File.read!(feed_path(source))
      assert String.contains?(feed, "#{present.uuid}")
      refute String.contains?(feed, "/nonexistent/")
    end

    test "leaves no stray temp files behind", %{source: source} do
      downloaded_episode(source, "Title [id].mp3")

      assert :ok = PodcastExport.export_source(source, @url_base)
      assert :ok = PodcastExport.export_source(source, @url_base)

      leftover =
        [PodcastExport.podcast_directory(), "lex-fridman"]
        |> Path.join()
        |> File.ls!()
        |> Enum.filter(&String.ends_with?(&1, ".tmp"))

      assert leftover == []
    end
  end

  describe "prune_source/1" do
    test "removes the generated feed and cover but leaves the media", %{source: source} do
      media_item = downloaded_episode(source, "Title [id].mp3")
      assert :ok = PodcastExport.export_source(source, @url_base)
      assert File.exists?(feed_path(source))

      assert :ok = PodcastExport.prune_source(source)

      refute File.exists?(feed_path(source))
      assert File.exists?(media_item.media_filepath)
    end

    test "removes the slug directory once it holds only generated files", %{source: source} do
      # No media downloaded — the directory only ever held feed.xml/cover
      assert :ok = PodcastExport.export_source(source, @url_base)
      assert File.dir?(slug_dir(source))

      assert :ok = PodcastExport.prune_source(source)
      refute File.dir?(slug_dir(source))
    end
  end

  describe "handle_source_deleted/1" do
    test "removes generated files and rewrites the OPML", %{source: source} do
      Settings.set(podcast_url_base: @url_base)
      assert :ok = PodcastExport.export_source(source, @url_base)

      assert :ok = PodcastExport.handle_source_deleted(source)

      refute File.exists?(feed_path(source))
      assert File.exists?(Path.join(PodcastExport.podcast_directory(), "opml.xml"))
    end
  end

  describe "write_opml/1" do
    test "lists published sources with their static feed URLs", %{source: source} do
      other = source_fixture(%{media_profile_id: media_profile_fixture(%{podcast_enabled: false}).id})

      assert :ok = PodcastExport.write_opml(@url_base)

      opml = File.read!(Path.join(PodcastExport.podcast_directory(), "opml.xml"))
      assert String.contains?(opml, "#{@url_base}/#{source.slug}/feed.xml")
      refute String.contains?(opml, "/#{other.slug}/feed.xml")
    end
  end

  describe "sweep/0" do
    test "errors when no URL base is configured" do
      assert {:error, :no_url_base} = PodcastExport.sweep()
    end

    test "regenerates feeds and writes the OPML", %{source: source} do
      Settings.set(podcast_url_base: @url_base)
      downloaded_episode(source, "Title [id].mp3")

      assert :ok = PodcastExport.sweep()

      assert File.exists?(feed_path(source))
      assert File.exists?(Path.join(PodcastExport.podcast_directory(), "opml.xml"))
    end

    test "removes generated feeds for directories no longer published", %{source: source} do
      Settings.set(podcast_url_base: @url_base)
      assert :ok = PodcastExport.export_source(source, @url_base)

      # Flip the profile off so the source no longer publishes
      {:ok, _} =
        source
        |> Repo.preload(:media_profile)
        |> Map.fetch!(:media_profile)
        |> Ecto.Changeset.change(%{podcast_enabled: false})
        |> Repo.update()

      assert :ok = PodcastExport.sweep()
      refute File.exists?(feed_path(source))
    end

    test "leaves unrelated directories under the library alone" do
      Settings.set(podcast_url_base: @url_base)
      unrelated = Path.join(PodcastExport.podcast_directory(), "not-a-podcast")
      File.mkdir_p!(unrelated)

      assert :ok = PodcastExport.sweep()
      assert File.dir?(unrelated)
    end
  end

  defp downloaded_episode(source, filename) do
    dir = slug_dir(source)
    media = Path.join(dir, filename)
    thumb = Path.join(dir, Path.rootname(filename) <> ".jpg")

    FilesystemUtils.cp_p!(media_filepath_fixture(), media)
    FilesystemUtils.cp_p!(thumbnail_filepath_fixture(), thumb)

    media_item_fixture(%{
      source_id: source.id,
      media_filepath: media,
      thumbnail_filepath: thumb,
      media_size_bytes: 100
    })
  end

  defp slug_dir(source), do: Path.join(PodcastExport.podcast_directory(), source.slug)
  defp feed_path(source), do: Path.join(slug_dir(source), "feed.xml")
end
