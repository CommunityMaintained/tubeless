defmodule Pinchflat.Podcasts.OpmlFeedBuilder do
  @moduledoc """
  Methods for building an OPML feed for a list of sources.
  """

  import Pinchflat.Utils.XmlUtils, only: [safe: 1]

  alias Pinchflat.Podcasts.DynamicFeedLinks

  @doc """
  Builds an OPML feed for a given list of sources.

  ## Options:
    - `:link_module` - The module that builds each feed's URL. Defaults to
      `DynamicFeedLinks` (URLs served by Tubeless itself); the static podcast
      export passes `StaticFeedLinks` instead.

  Returns an XML document as a string.
  """
  def build(url_base, sources, opts \\ []) do
    link_module = Keyword.get(opts, :link_module, DynamicFeedLinks)

    sources_xml =
      Enum.map(
        sources,
        &"""
        <outline type="rss" text="#{safe(&1.custom_name)}" xmlUrl="#{safe(link_module.opml_feed_url(url_base, &1))}" />
        """
      )

    """
    <?xml version="1.0" encoding="UTF-8"?>
    <opml version="2.0">
      <head>
        <title>All Sources</title>
      </head>
      <body>
        #{Enum.join(sources_xml, "\n")}
      </body>
    </opml>
    """
  end
end
