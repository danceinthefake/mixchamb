defmodule MixwaveWeb.LibraryLive do
  @moduledoc """
  Public song library — every visitor sees every song. Newest first.
  """
  use MixwaveWeb, :live_view

  alias Mixwave.Library

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :songs, Library.list_songs())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Library
        <:subtitle>
          {if @current_user, do: "you are #{@current_user.display_name}", else: "anonymous"}
        </:subtitle>
        <:actions>
          <.button navigate={~p"/upload"}>Upload a song</.button>
        </:actions>
      </.header>

      <div :if={@songs == []} class="rounded-lg border border-dashed py-16 text-center">
        <p class="text-muted-foreground">No songs yet. Be the first.</p>
        <.button class="mt-4" navigate={~p"/upload"}>Upload</.button>
      </div>

      <ul :if={@songs != []} class="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <li
          :for={song <- @songs}
          class="rounded-lg border bg-card p-4 hover:bg-accent transition-colors"
        >
          <.link navigate={~p"/song/#{song.id}"} class="block">
            <h3 class="font-semibold truncate">{song.title}</h3>
            <p :if={song.genre} class="mt-1 text-xs uppercase tracking-wide text-muted-foreground">
              {song.genre}
            </p>
            <p class="mt-2 text-sm text-muted-foreground">
              by {song.user.display_name}
            </p>
          </.link>
        </li>
      </ul>
    </Layouts.app>
    """
  end
end
