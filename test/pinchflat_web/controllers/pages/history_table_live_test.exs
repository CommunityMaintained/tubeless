defmodule PinchflatWeb.Pages.HistoryTableLiveTest do
  use PinchflatWeb.ConnCase

  import Phoenix.LiveViewTest
  import Pinchflat.MediaFixtures
  import Pinchflat.SourcesFixtures

  alias Pinchflat.Pages.HistoryTableLive

  describe "lazy loading" do
    test "renders a loading placeholder until the LazyTab hook fires", %{conn: conn} do
      media_item = media_item_fixture(title: "Downloaded Video")

      {:ok, view, html} = live_isolated(conn, HistoryTableLive, session: %{"media_state" => "downloaded"})

      assert html =~ "Loading..."
      refute html =~ media_item.title

      html = render_hook(view, "lazy_load")

      refute html =~ "Loading..."
      assert html =~ media_item.title
    end

    test "loads eagerly (no hook, immediate content) when lazy is false", %{conn: conn} do
      media_item = media_item_fixture(title: "Downloaded Video")

      {:ok, view, html} =
        live_isolated(conn, HistoryTableLive, session: %{"media_state" => "downloaded", "lazy" => false})

      refute html =~ "Loading..."
      refute html =~ "LazyTab"
      assert html =~ media_item.title

      # eager tables refetch on job:state changes without any lazy_load event
      other_media_item = media_item_fixture(title: "Another Video")
      PinchflatWeb.Endpoint.broadcast("job:state", "change", nil)

      assert render(view) =~ other_media_item.title
    end

    test "a duplicate lazy_load event is harmless", %{conn: conn} do
      media_item = media_item_fixture(title: "Downloaded Video")

      {view, _html} = mount_and_load(conn, %{"media_state" => "downloaded"})
      html = render_hook(view, "lazy_load")

      assert html =~ media_item.title
    end

    test "does not refetch on job:state changes before loading", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, HistoryTableLive, session: %{"media_state" => "downloaded"})

      media_item = media_item_fixture()
      PinchflatWeb.Endpoint.broadcast("job:state", "change", nil)

      refute render(view) =~ media_item.title
    end
  end

  describe "initial rendering" do
    test "shows a message when there are no records", %{conn: conn} do
      {_view, html} = mount_and_load(conn, %{"media_state" => "downloaded"})

      assert html =~ "Nothing Here!"
    end

    test "shows downloaded media when the media_state is downloaded", %{conn: conn} do
      media_item = media_item_fixture(title: "Downloaded Video")

      {_view, html} = mount_and_load(conn, %{"media_state" => "downloaded"})

      assert html =~ media_item.title
    end

    test "does not show pending media when the media_state is downloaded", %{conn: conn} do
      media_item = media_item_fixture(title: "Pending Video", media_filepath: nil)

      {_view, html} = mount_and_load(conn, %{"media_state" => "downloaded"})

      refute html =~ media_item.title
    end

    test "shows pending media when the media_state is pending", %{conn: conn} do
      media_item = media_item_fixture(title: "Pending Video", media_filepath: nil)

      {_view, html} = mount_and_load(conn, %{"media_state" => "pending"})

      assert html =~ media_item.title
    end

    test "links each record to its media item and source", %{conn: conn} do
      media_item = media_item_fixture()

      {_view, html} = mount_and_load(conn, %{"media_state" => "downloaded"})

      assert html =~ ~p"/sources/#{media_item.source_id}/media/#{media_item.id}"
      assert html =~ ~p"/sources/#{media_item.source_id}"
    end
  end

  describe "pagination" do
    test "paginates past the per-page limit", %{conn: conn} do
      source = source_fixture()
      # The table shows 5 records per page, newest first
      Enum.each(1..6, fn n -> media_item_fixture(source_id: source.id, title: "Video #{n}") end)

      {view, html} = mount_and_load(conn, %{"media_state" => "downloaded"})

      assert html =~ "Video 6"
      refute html =~ "Video 1"

      html = render_click(view, "page_change", %{"direction" => "inc"})

      assert html =~ "Video 1"
      refute html =~ "Video 6"
    end

    test "clamps the page number so it can't go below the first page", %{conn: conn} do
      media_item = media_item_fixture()

      {view, _html} = mount_and_load(conn, %{"media_state" => "downloaded"})

      html = render_click(view, "page_change", %{"direction" => "dec"})

      assert html =~ media_item.title
    end
  end

  describe "reloading" do
    test "reload_page refetches the current records", %{conn: conn} do
      {view, html} = mount_and_load(conn, %{"media_state" => "downloaded"})
      assert html =~ "Nothing Here!"

      media_item = media_item_fixture()

      html = render_click(view, "reload_page")

      assert html =~ media_item.title
    end

    test "refetches records on job:state change events", %{conn: conn} do
      {view, html} = mount_and_load(conn, %{"media_state" => "downloaded"})
      assert html =~ "Nothing Here!"

      media_item = media_item_fixture()
      PinchflatWeb.Endpoint.broadcast("job:state", "change", nil)

      assert render(view) =~ media_item.title
    end
  end

  defp mount_and_load(conn, session) do
    {:ok, view, _html} = live_isolated(conn, HistoryTableLive, session: session)
    html = render_hook(view, "lazy_load")

    {view, html}
  end
end
