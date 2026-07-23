defmodule Pinchflat.Podcasts.PodcastSweepWorkerTest do
  use Pinchflat.DataCase

  import Pinchflat.SourcesFixtures
  import Pinchflat.ProfilesFixtures

  alias Pinchflat.Settings
  alias Pinchflat.Podcasts.PodcastExport
  alias Pinchflat.Podcasts.PodcastSweepWorker
  alias Pinchflat.Utils.FilesystemUtils

  @url_base "http://pods.local"

  setup do
    on_exit(fn -> File.rm_rf!(PodcastExport.podcast_directory()) end)

    :ok
  end

  describe "kickoff/0" do
    test "enqueues a sweep job" do
      assert {:ok, %Oban.Job{}} = PodcastSweepWorker.kickoff()

      assert_enqueued(worker: PodcastSweepWorker)
    end

    test "dedupes against a pending sweep" do
      assert {:ok, _} = PodcastSweepWorker.kickoff()
      assert {:ok, _} = PodcastSweepWorker.kickoff()

      assert [_] = all_enqueued(worker: PodcastSweepWorker)
    end

    test "schedules a follow-up while a sweep is executing" do
      # A URL-base change mid-sweep must not be swallowed: executing is excluded
      # from uniqueness so a follow-up still queues
      {:ok, executing_job} = PodcastSweepWorker.kickoff()
      Repo.update_all(from(j in Oban.Job, where: j.id == ^executing_job.id), set: [state: "executing"])

      assert {:ok, followup} = PodcastSweepWorker.kickoff()
      assert followup.id != executing_job.id
    end
  end

  describe "perform/1" do
    test "cancels when the URL base isn't set" do
      assert {:cancel, _} = perform_job(PodcastSweepWorker, %{})
    end

    test "regenerates published feeds and prunes orphaned generated feeds" do
      Settings.set(podcast_url_base: @url_base)
      profile = media_profile_fixture(%{podcast_enabled: true})
      source = source_fixture(%{media_profile_id: profile.id})

      # A leftover generated feed whose slug no longer maps to a published source
      orphan_feed = Path.join([PodcastExport.podcast_directory(), "orphan-slug", "feed.xml"])
      FilesystemUtils.write_p!(orphan_feed, "<xml/>")

      assert :ok = perform_job(PodcastSweepWorker, %{})

      assert File.exists?(Path.join([PodcastExport.podcast_directory(), source.slug, "feed.xml"]))
      refute File.exists?(orphan_feed)
    end
  end
end
