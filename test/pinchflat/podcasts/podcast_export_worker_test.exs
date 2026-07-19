defmodule Pinchflat.Podcasts.PodcastExportWorkerTest do
  use Pinchflat.DataCase

  import Pinchflat.MediaFixtures
  import Pinchflat.SourcesFixtures
  import Pinchflat.ProfilesFixtures

  alias Pinchflat.Settings
  alias Pinchflat.Podcasts.PodcastExport
  alias Pinchflat.Podcasts.PodcastExportWorker
  alias Pinchflat.Utils.FilesystemUtils

  @url_base "http://pods.local"

  setup do
    profile = media_profile_fixture(%{podcast_enabled: true})
    source = source_fixture(%{media_profile_id: profile.id})

    on_exit(fn -> File.rm_rf!(PodcastExport.podcast_directory()) end)

    {:ok, profile: profile, source: source}
  end

  describe "kickoff/1" do
    test "enqueues a job for a published source", %{source: source} do
      assert {:ok, %Oban.Job{}} = PodcastExportWorker.kickoff(source)

      assert_enqueued(worker: PodcastExportWorker, args: %{"source_id" => source.id})
    end

    test "no-ops for a non-podcast source with no generated feed" do
      profile = media_profile_fixture(%{podcast_enabled: false})
      source = source_fixture(%{media_profile_id: profile.id})

      assert :ok = PodcastExportWorker.kickoff(source)
      refute_enqueued(worker: PodcastExportWorker)
    end

    test "enqueues for a non-podcast source whose generated feed needs pruning" do
      profile = media_profile_fixture(%{podcast_enabled: false})
      source = source_fixture(%{media_profile_id: profile.id})
      write_feed(source)

      assert {:ok, %Oban.Job{}} = PodcastExportWorker.kickoff(source)
      assert_enqueued(worker: PodcastExportWorker, args: %{"source_id" => source.id})
    end

    test "deduplicates repeated kickoffs", %{source: source} do
      assert {:ok, _} = PodcastExportWorker.kickoff(source)
      assert {:ok, _} = PodcastExportWorker.kickoff(source)

      assert [_] = all_enqueued(worker: PodcastExportWorker)
    end

    test "a follow-up can be scheduled while an export is executing", %{source: source} do
      # An executing job doesn't dedupe a new kickoff (executing is excluded
      # from uniqueness), so a change landing mid-export isn't lost
      {:ok, executing_job} = PodcastExportWorker.kickoff(source)
      Repo.update_all(from(j in Oban.Job, where: j.id == ^executing_job.id), set: [state: "executing"])

      assert {:ok, followup} = PodcastExportWorker.kickoff(source)
      assert followup.id != executing_job.id
    end
  end

  describe "kickoff_deletion/1" do
    test "enqueues a cleanup job carrying the slug when a feed exists", %{source: source} do
      write_feed(source)

      assert {:ok, %Oban.Job{}} = PodcastExportWorker.kickoff_deletion(source)
      assert_enqueued(worker: PodcastExportWorker, args: %{"deleted_source_slug" => source.slug})
    end

    test "no-ops when nothing was ever published and no URL base is set", %{source: source} do
      assert :ok = PodcastExportWorker.kickoff_deletion(source)
      refute_enqueued(worker: PodcastExportWorker)
    end
  end

  describe "perform/1" do
    test "writes the source's feed and OPML", %{source: source} do
      Settings.set(podcast_url_base: @url_base)
      downloaded_episode(source)

      perform_job(PodcastExportWorker, %{source_id: source.id})

      assert File.exists?(feed_path(source))
      assert File.exists?(Path.join(PodcastExport.podcast_directory(), "opml.xml"))
    end

    test "cancels when the URL base isn't set", %{source: source} do
      assert {:cancel, _} = perform_job(PodcastExportWorker, %{source_id: source.id})
    end

    test "prunes the generated feed of a source that stopped publishing", %{source: source} do
      Settings.set(podcast_url_base: @url_base)
      perform_job(PodcastExportWorker, %{source_id: source.id})
      assert File.exists?(feed_path(source))

      {:ok, _} =
        source
        |> Repo.preload(:media_profile)
        |> Map.fetch!(:media_profile)
        |> Ecto.Changeset.change(%{podcast_enabled: false})
        |> Repo.update()

      perform_job(PodcastExportWorker, %{source_id: source.id})
      refute File.exists?(feed_path(source))
    end

    test "no-ops when the source has been deleted" do
      assert :ok = perform_job(PodcastExportWorker, %{source_id: 0})
    end

    test "the deletion clause prunes the generated feed and rewrites the OPML", %{source: source} do
      Settings.set(podcast_url_base: @url_base)
      perform_job(PodcastExportWorker, %{source_id: source.id})
      assert File.exists?(feed_path(source))

      # Simulate the source having been deleted, then run the queued cleanup
      Repo.delete(source)
      assert :ok = perform_job(PodcastExportWorker, %{deleted_source_slug: source.slug})

      refute File.exists?(feed_path(source))
      assert File.exists?(Path.join(PodcastExport.podcast_directory(), "opml.xml"))
    end
  end

  defp downloaded_episode(source) do
    media = Path.join([PodcastExport.podcast_directory(), source.slug, "Episode [id].mp4"])
    FilesystemUtils.cp_p!(media_filepath_fixture(), media)
    media_item_fixture(%{source_id: source.id, media_filepath: media, media_size_bytes: 100})
  end

  defp write_feed(source) do
    FilesystemUtils.write_p!(feed_path(source), "<xml/>")
  end

  defp feed_path(source) do
    Path.join([PodcastExport.podcast_directory(), source.slug, "feed.xml"])
  end
end
