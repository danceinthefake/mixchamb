defmodule MixwaveWeb.UploadLive do
  @moduledoc """
  Upload page — placeholder. Real implementation lands in the next
  commit (drag-and-drop with LiveView allow_upload + presigned PUT
  to R2).
  """
  use MixwaveWeb, :live_view

  @impl true
  def mount(_params, _session, socket), do: {:ok, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Upload
        <:subtitle>Drop an audio file to upload (wiring pending).</:subtitle>
      </.header>

      <p class="text-muted-foreground">Implementation coming next.</p>
    </Layouts.app>
    """
  end
end
