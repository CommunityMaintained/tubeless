defmodule Pinchflat.Podcasts.PodcastSweepWorker do
  @moduledoc false

  use Oban.Worker,
    queue: :podcast_export,
    tags: ["sources", "podcast_export"]

  alias __MODULE__
  alias Pinchflat.Podcasts.PodcastExport

  # Excludes `:executing` (like `PodcastExportWorker`) so a URL-base change made
  # while a sweep is running still schedules a follow-up rather than being
  # dropped until the daily cron. Set at insert time instead of in the macro to
  # avoid the Oban advisory warning tripping `--warnings-as-errors`. The daily
  # cron enqueue goes through `new/0` without this, which is fine — cron runs
  # are a day apart so they can't collide with each other.
  @unique [period: :infinity, states: [:available, :scheduled, :retryable]]

  @doc """
  Enqueues a full podcast export reconcile.

  Returns {:ok, %Oban.Job{}}
  """
  def kickoff do
    Oban.insert(PodcastSweepWorker.new(%{}, unique: @unique))
  end

  @doc """
  Re-exports every export-enabled source, prunes directories of sources
  that are disabled or deleted, and rewrites the OPML document. Runs daily
  (see the crontab in `config/runtime.exs`) as the safety net behind the
  event-driven per-source exports.

  Returns :ok | {:cancel, binary()}
  """
  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    case PodcastExport.sweep() do
      # Not being set up for podcast exports at all is the normal state for
      # most instances, so a scheduled sweep quietly cancelling is expected
      {:error, :no_url_base} -> {:cancel, "The podcast URL base setting is not set"}
      :ok -> :ok
    end
  end
end
