defmodule PinchflatWeb.Sources.SourceLive.SourceEnableToggle do
  use PinchflatWeb, :live_component

  alias Pinchflat.Sources
  alias Pinchflat.Sources.Source

  def render(assigns) do
    ~H"""
    <div>
      <.form
        :let={f}
        for={@form}
        id={"source_#{@source_id}_enabled_toggle_form"}
        phx-change="update"
        phx-target={@myself}
        class="enabled_toggle_form"
      >
        <.input id={"source_#{@source_id}_enabled_input"} field={f[:enabled]} type="toggle" />
      </.form>
    </div>
    """
  end

  def update(assigns, socket) do
    # Only `enabled` is rendered, and changeset params must be a plain map —
    # passing the source record itself would crash `cast` if it's ever a
    # %Source{} struct (it happens to be a bare map from the index query today)
    initial_data = %{
      source_id: assigns.source.id,
      form: Sources.change_source(%Source{}, Map.take(assigns.source, [:enabled]))
    }

    socket
    |> assign(initial_data)
    |> then(&{:ok, &1})
  end

  def handle_event("update", %{"source" => source_params}, %{assigns: assigns} = socket) do
    assigns.source_id
    |> Sources.get_source!()
    |> Sources.update_source(source_params)

    {:noreply, socket}
  end
end
