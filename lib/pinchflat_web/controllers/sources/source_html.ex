defmodule PinchflatWeb.Sources.SourceHTML do
  use PinchflatWeb, :html

  embed_templates "source_html/*"

  @doc """
  Renders a source form.
  """
  attr :changeset, Ecto.Changeset, required: true
  attr :action, :string, required: true
  attr :media_profiles, :list, required: true
  attr :method, :string, required: true

  def source_form(assigns)

  def friendly_index_frequencies do
    [
      {"Only once when first created", -1},
      {"30 minutes", 30},
      {"1 Hour", 60},
      {"3 Hours", 3 * 60},
      {"6 Hours", 6 * 60},
      {"12 Hours", 12 * 60},
      {"Daily (recommended)", 24 * 60},
      {"Weekly", 7 * 24 * 60},
      {"Monthly", 30 * 24 * 60}
    ]
  end

  def friendly_cookie_behaviours do
    [
      {"Disabled", :disabled},
      {"When Needed", :when_needed},
      {"All Operations", :all_operations}
    ]
  end

  def cutoff_date_presets do
    [
      {"7 days", compute_date_offset(7)},
      {"14 days", compute_date_offset(14)},
      {"30 days", compute_date_offset(30)},
      {"60 days", compute_date_offset(60)},
      {"90 days", compute_date_offset(90)},
      {"180 days", compute_date_offset(180)},
      {"365 days", compute_date_offset(365)}
    ]
  end

  def rss_feed_url(conn, source) do
    # NOTE: The reason for this concatenation is to avoid what appears to be a bug in Phoenix
    # See: https://github.com/phoenixframework/phoenix/issues/6033
    url(conn, ~p"/sources/#{source.uuid}/feed") <> ".xml"
  end

  # The feed URL on the external static file server, or nil unless the source is
  # published as a podcast, the podcast URL base has been configured, AND the
  # feed has actually been generated on disk. Export is debounced (~30s) and can
  # fail, so gating on the real feed.xml keeps us from advertising a URL that
  # would 404 (or stay broken after a failed export).
  def static_podcast_feed_url(source) do
    url_base = Settings.get!(:podcast_url_base)

    if url_base && source.slug && Pinchflat.Podcasts.PodcastExport.enabled?(source) &&
         Pinchflat.Podcasts.PodcastExport.feed_generated?(source) do
      Pinchflat.Podcasts.StaticFeedLinks.self_url(url_base, source)
    else
      nil
    end
  end

  # True when the source is configured to publish as a podcast (URL base set) but
  # the feed hasn't been generated on disk yet — the export is debounced and runs
  # in the background, so the page shows a "pending" note instead of a dead URL.
  def static_podcast_feed_pending?(source) do
    Settings.get!(:podcast_url_base) && source.slug &&
      Pinchflat.Podcasts.PodcastExport.enabled?(source) &&
      !Pinchflat.Podcasts.PodcastExport.feed_generated?(source)
  end

  # The on-disk directory Tubeless wrote the feed/cover/media into. This is what
  # the external static web server must serve as the podcast's slug folder — the
  # feed URL only works once that server is pointed at the podcast library.
  def static_podcast_local_path(source) do
    Path.join(Pinchflat.Podcasts.PodcastExport.podcast_directory(), source.slug)
  end

  # True when the source should publish as a podcast but feeds can't be generated
  # because the "Podcast URL Base" setting is empty — surfaced as a warning so the
  # silent export cancellations aren't a mystery
  def podcast_missing_url_base?(source) do
    Pinchflat.Podcasts.PodcastExport.enabled?(source) && is_nil(Settings.get!(:podcast_url_base))
  end

  def opml_feed_url(conn) do
    url(conn, ~p"/sources/opml.xml?#{[route_token: Settings.get!(:route_token)]}")
  end

  def output_path_template_override_placeholders(media_profiles) do
    media_profiles
    |> Enum.map(&{&1.id, &1.output_path_template})
    |> Map.new()
    |> Phoenix.json_library().encode!()
  end

  def title_filter_regex_help do
    url = "https://github.com/nalgeon/sqlean/blob/main/docs/regexp.md#supported-syntax"
    classes = "underline decoration-bodydark decoration-1 hover:decoration-white"

    """
    A PCRE-compatible regex. Only media with titles that match this regex will be downloaded. <a href="#{url}" class="#{classes}" target="_blank">See here</a> for syntax
    """
  end

  def output_path_template_override_help do
    help_button_classes = "underline decoration-bodydark decoration-1 hover:decoration-white cursor-pointer"
    help_button = ~s{<span class="#{help_button_classes}" x-on:click="$dispatch('load-template')">Click here</span>}

    """
    Must end with .{{ ext }}. Same rules as Media Profile output path templates. #{help_button} to load your media profile's output template
    """
  end

  defp compute_date_offset(days) do
    timezone = Application.get_env(:pinchflat, :timezone)

    timezone
    |> Timex.now()
    |> Timex.shift(days: -days)
    |> Timex.format!("{YYYY}-{0M}-{0D}")
  end
end
