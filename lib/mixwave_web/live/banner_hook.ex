defmodule MixwaveWeb.Live.BannerHook do
  @moduledoc """
  on_mount hook that wires every browser LV to the admin-broadcast
  banner system:

    * Reads the currently-active banner from the DB once on mount
      so the first paint already includes it (or nil).
    * Subscribes the LV process to `Mixwave.Banners.topic/0` so a
      later set or clear is pushed out in real time.

  LVs that mount under this hook can render `@banner` directly;
  the layout (`Layouts.app/1`) consumes it.

  Pair with a `handle_info({:banner_changed, banner}, socket)`
  clause in any LV that wants the banner to live-update — or
  rely on the layout-level handler we plant via attach_hook below.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4, connected?: 1]

  alias Mixwave.Banners

  def on_mount(:default, _params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Mixwave.PubSub, Banners.topic())
    end

    socket =
      socket
      |> assign(:banner, Banners.current_banner())
      |> attach_hook(:banner_listener, :handle_info, &handle_info/2)

    {:cont, socket}
  end

  # Plant a handle_info hook so every LV under this on_mount picks
  # up banner changes without needing to wire its own clause. The
  # hook returns :cont so the LV's own handle_info clauses still
  # run for unrelated messages.
  defp handle_info({:banner_changed, banner}, socket) do
    {:cont, assign(socket, :banner, banner)}
  end

  defp handle_info(_other, socket), do: {:cont, socket}
end
