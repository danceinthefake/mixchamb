defmodule MixwaveWeb.ManageLive do
  @moduledoc """
  Manage page — your songs, edit/delete. Placeholder.
  """
  use MixwaveWeb, :live_view

  alias Mixwave.Library

  @impl true
  def mount(_params, _session, socket) do
    songs =
      case socket.assigns[:current_user] do
        nil -> []
        user -> Library.list_user_songs(user.id)
      end

    {:ok, assign(socket, :songs, songs)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Your songs
        <:subtitle>
          {if @current_user, do: "uploaded by #{@current_user.display_name}", else: "no user"}
        </:subtitle>
      </.header>

      <p :if={@songs == []} class="text-muted-foreground">
        You haven't uploaded anything yet.
        <.link navigate={~p"/upload"} class="underline">Upload one</.link>.
      </p>

      <ul :if={@songs != []} class="divide-y rounded-md border">
        <li :for={song <- @songs} class="px-4 py-3 flex items-center justify-between">
          <div>
            <p class="font-medium">{song.title}</p>
            <p :if={song.genre} class="text-xs text-muted-foreground">{song.genre}</p>
          </div>
          <.link navigate={~p"/song/#{song.id}"} class="text-sm underline">View</.link>
        </li>
      </ul>
    </Layouts.app>
    """
  end
end
