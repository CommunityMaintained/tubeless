defmodule Pinchflat.Podcasts.PodcastExportWorker do
  @moduledoc false

  use Oban.Worker,
    queue: :podcast_export,
    tags: ["sources", "podcast_export"]

  alias __MODULE__
  alias Pinchflat.Repo
  alias Pinchflat.Sources.Source
  alias Pinchflat.Podcasts.PodcastExport

  @debounce_seconds 30

  # Coalesces bursts (eg: a batch of downloads finishing) into one run: while a
  # job is pending, further kickoffs dedupe against it. `:executing` is
  # deliberately excluded so a change landing *during* an export still schedules
  # a follow-up rather than being dropped until the daily sweep; the
  # single-concurrency `podcast_export` queue then runs that follow-up strictly
  # after the current one, so exports never overlap. Uniqueness is set here at
  # insert time rather than in `use Oban.Worker` to avoid the compile-time
  # advisory warning about excluding incomplete states (which is exactly what we
  # want here) tripping `--warnings-as-errors`.
  @unique [period: :infinity, states: [:available, :scheduled, :retryable]]

  @doc """
  Enqueues a debounced export run for the given source. No-ops when the
  source neither is export-enabled nor has an old export directory that
  would need pruning, so calling this from content-change paths is cheap
  for non-podcast users.

  Returns {:ok, %Oban.Job{}} | :ok
  """
  def kickoff(source) do
    directory = Path.join(PodcastExport.podcast_directory(), source.slug || "")

    if PodcastExport.enabled?(source) || generated_feed?(directory) do
      %{source_id: source.id}
      |> PodcastExportWorker.new(schedule_in: @debounce_seconds, unique: @unique)
      |> Oban.insert()
    else
      :ok
    end
  end

  @doc """
  Enqueues cleanup of a just-deleted source's generated feed files and OPML entry.

  This runs through the same single-concurrency queue as exports (rather than
  synchronously in `delete_source`) so it can't race an export/sweep that is
  already executing with a pre-deletion snapshot: the concurrency-1 queue makes
  the cleanup run strictly *after* any in-flight export, and `perform/1`'s
  existence check makes any later-scheduled export for the deleted source a
  no-op. The stable slug is carried because the source row is already gone.

  Returns {:ok, %Oban.Job{}} | :ok
  """
  def kickoff_deletion(source) do
    directory = Path.join(PodcastExport.podcast_directory(), source.slug || "")

    # Nothing to clean up for a source that was never published and can't be in
    # the OPML document (no URL base configured)
    if generated_feed?(directory) || PodcastExport.url_base() do
      %{deleted_source_slug: source.slug}
      |> PodcastExportWorker.new()
      |> Oban.insert()
    else
      :ok
    end
  end

  defp generated_feed?(directory) do
    File.exists?(Path.join(directory, PodcastExport.feed_filename()))
  end

  @doc """
  Exports (or prunes) the static podcast files for a single source and
  rewrites the shared OPML document.

  Returns :ok | {:cancel, binary()}
  """
  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"deleted_source_slug" => slug}}) do
    PodcastExport.handle_source_deleted(%Source{slug: slug})
  end

  def perform(%Oban.Job{args: %{"source_id" => source_id}}) do
    case Repo.get(Source, source_id) do
      # The source was deleted after this job was enqueued; its directory is
      # cleaned up by the deletion job (or the daily sweep)
      nil ->
        :ok

      source ->
        export_or_prune(source)
    end
  end

  defp export_or_prune(source) do
    cond do
      !PodcastExport.enabled?(source) ->
        PodcastExport.prune_source(source)
        maybe_write_opml()

      is_nil(PodcastExport.url_base()) ->
        {:cancel, "Podcast export is enabled but the podcast URL base setting is not set"}

      true ->
        PodcastExport.export_source(source, PodcastExport.url_base())
        maybe_write_opml()
    end
  end

  defp maybe_write_opml do
    case PodcastExport.url_base() do
      nil -> :ok
      url_base -> PodcastExport.write_opml(url_base)
    end
  end
end
