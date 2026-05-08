defmodule MixwaveWeb.SongLive do
  @moduledoc """
  Song detail — placeholder. Real implementation will show title,
  description, comments form + list, persistent player + waveform.
  """
  use MixwaveWeb, :live_view

  alias Mixwave.Library

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Library.get_song(id) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Song not found.")
         |> push_navigate(to: ~p"/")}

      song ->
        {:ok, assign(socket, :song, song)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        {@song.title}
        <:subtitle>by {@song.user.display_name}</:subtitle>
      </.header>

      <p :if={@song.description} class="text-muted-foreground">{@song.description}</p>
      <p class="mt-6 text-muted-foreground">Player + comments coming next.</p>
    </Layouts.app>
    """
  end
end
