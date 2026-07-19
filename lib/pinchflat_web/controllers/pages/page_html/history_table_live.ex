defmodule Pinchflat.Pages.HistoryTableLive do
  use PinchflatWeb, :live_view
  use Pinchflat.Media.MediaQuery

  alias Pinchflat.Repo
  alias Pinchflat.Utils.NumberUtils
  alias PinchflatWeb.CustomComponents.TextComponents

  @limit 5

  # The un-loaded state renders the LazyTab hook element: this LiveView lives in
  # a tab on the home page, so it defers all data queries until the hook reports
  # the tab is actually visible and pushes "lazy_load". Notably, this keeps the
  # hidden "Pending" tab from re-running its expensive query on every job:state
  # broadcast unless the user actually opens it. The default-visible tab passes
  # `"lazy" => false` instead and loads eagerly (content in the initial HTML,
  # no LazyTab hook), since deferring a visible table only delays first paint
  def render(%{loaded: false} = assigns) do
    ~H"""
    <div id={"history-table-#{@media_state}"} phx-hook="LazyTab" class="mb-4 flex items-center">
      <p>Loading...</p>
    </div>
    """
  end

  def render(%{records: []} = assigns) do
    ~H"""
    <div id={"history-table-#{@media_state}"} phx-hook={@lazy && "LazyTab"} class="mb-4 flex items-center">
      <.icon_button icon_name="hero-arrow-path" class="h-10 w-10" phx-click="reload_page" />
      <p class="ml-2">Nothing Here!</p>
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <div id={"history-table-#{@media_state}"} phx-hook={@lazy && "LazyTab"}>
      <span class="mb-4 flex items-center">
        <.icon_button icon_name="hero-arrow-path" class="h-10 w-10" phx-click="reload_page" tooltip="Refresh" />
        <span class="ml-2">
          Showing <.localized_number number={length(@records)} /> of <.localized_number number={@total_record_count} />
        </span>
      </span>
      <div class="max-w-full overflow-x-auto">
        <.table rows={@records} table_class="text-white">
          <:col :let={media_item} label="Title" class="max-w-xs">
            <section class="flex items-center space-x-1">
              <.tooltip
                :if={media_item.last_error}
                tooltip={media_item.last_error}
                position="bottom-right"
                tooltip_class="w-64"
              >
                <.icon name="hero-exclamation-circle-solid" class="text-red-500" />
              </.tooltip>
              <span class="truncate">
                <.subtle_link href={~p"/sources/#{media_item.source_id}/media/#{media_item.id}"}>
                  {media_item.title}
                </.subtle_link>
              </span>
            </section>
          </:col>
          <:col :let={media_item} label="Upload Date">
            {DateTime.to_date(media_item.uploaded_at)}
          </:col>
          <:col :let={media_item} label="Indexed At">
            {format_datetime(media_item.inserted_at)}
          </:col>
          <:col :let={media_item} label="Downloaded At">
            {format_datetime(media_item.media_downloaded_at)}
          </:col>
          <:col :let={media_item} label="Source" class="truncate max-w-xs">
            <.subtle_link href={~p"/sources/#{media_item.source_id}"}>
              {media_item.source.custom_name}
            </.subtle_link>
          </:col>
        </.table>
      </div>
      <section class="flex justify-center mt-5">
        <.live_pagination_controls page_number={@page} total_pages={@total_pages} />
      </section>
    </div>
    """
  end

  def mount(_params, session, socket) do
    media_state = session["media_state"]
    lazy = Map.get(session, "lazy", true)
    base_query = generate_base_query(media_state)

    socket = assign(socket, %{base_query: base_query, media_state: media_state, lazy: lazy, loaded: not lazy})

    socket =
      if lazy do
        socket
      else
        if connected?(socket), do: PinchflatWeb.Endpoint.subscribe("job:state")

        assign(socket, fetch_pagination_attributes(base_query, 1))
      end

    {:ok, socket}
  end

  # Pushed by the LazyTab hook the first time this table's tab is visible.
  # Subscribing here (rather than in mount) means hidden tabs don't refetch
  # on job:state broadcasts. The loaded guard makes a stray duplicate event
  # harmless
  def handle_event("lazy_load", _params, %{assigns: %{loaded: true}} = socket), do: {:noreply, socket}

  def handle_event("lazy_load", _params, %{assigns: assigns} = socket) do
    PinchflatWeb.Endpoint.subscribe("job:state")

    new_assigns = fetch_pagination_attributes(assigns.base_query, 1)

    {:noreply, assign(socket, Map.put(new_assigns, :loaded, true))}
  end

  def handle_event("page_change", %{"direction" => direction}, %{assigns: assigns} = socket) do
    direction = if direction == "inc", do: 1, else: -1
    new_page = assigns.page + direction
    new_assigns = fetch_pagination_attributes(assigns.base_query, new_page)

    {:noreply, assign(socket, new_assigns)}
  end

  def handle_event("reload_page", _params, %{assigns: assigns} = socket) do
    new_assigns = fetch_pagination_attributes(assigns.base_query, assigns.page)

    {:noreply, assign(socket, new_assigns)}
  end

  def handle_info(%{topic: "job:state", event: "change"}, %{assigns: assigns} = socket) do
    new_assigns = fetch_pagination_attributes(assigns.base_query, assigns.page)

    {:noreply, assign(socket, new_assigns)}
  end

  defp fetch_pagination_attributes(base_query, page) do
    total_record_count = Repo.aggregate(base_query, :count, :id)
    total_pages = max(ceil(total_record_count / @limit), 1)
    page = NumberUtils.clamp(page, 1, total_pages)
    records = fetch_records(base_query, page)

    %{page: page, total_pages: total_pages, records: records, total_record_count: total_record_count}
  end

  defp fetch_records(base_query, page) do
    offset = (page - 1) * @limit

    base_query
    |> limit(^@limit)
    |> offset(^offset)
    |> Repo.all()
    |> Repo.preload(:source)
  end

  defp generate_base_query("pending") do
    MediaQuery.new()
    |> MediaQuery.require_assoc(:media_profile)
    |> where(^dynamic(^MediaQuery.pending()))
    |> order_by(desc: :id)
  end

  defp generate_base_query("downloaded") do
    MediaQuery.new()
    |> MediaQuery.require_assoc(:media_profile)
    |> where(^dynamic(^MediaQuery.downloaded()))
    |> order_by(desc: :id)
  end

  defp format_datetime(nil), do: ""

  defp format_datetime(datetime) do
    TextComponents.datetime_in_zone(%{datetime: datetime, format: "%Y-%m-%d %H:%M"})
  end
end
