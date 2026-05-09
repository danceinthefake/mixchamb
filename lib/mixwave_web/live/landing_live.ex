defmodule MixwaveWeb.LandingLive do
  @moduledoc """
  The "/" page. Pre-jam landing — explains the chamber model and
  offers a single primary action ("Create a chamber") that creates
  a row, generates a fresh slug, and pushes the user into the
  chamber's URL.
  """
  use MixwaveWeb, :live_view

  alias Mixwave.Chambers

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_event("create_chamber", _params, socket) do
    user = socket.assigns.current_user

    case Chambers.create_chamber(user.id) do
      {:ok, chamber} ->
        {:noreply, push_navigate(socket, to: ~p"/chamber/#{chamber.slug}")}

      {:error, _changeset} ->
        # Slug collision is the only realistic failure here, and
        # it's vanishingly unlikely. Surface a generic flash and
        # let the user try again.
        {:noreply, put_flash(socket, :error, "Couldn't create the chamber. Try again.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="-mx-4 sm:-mx-6 lg:-mx-8 -my-10 px-4 sm:px-6 lg:px-8 py-16 min-h-[calc(100dvh-3.5rem)] flex items-center justify-center">
        <div class="w-full max-w-md text-center space-y-8">
          <img
            src={~p"/images/logo.svg"}
            alt=""
            class="size-20 mx-auto"
          />
          <div class="space-y-3">
            <h1 class="text-4xl font-bold tracking-tight font-display">
              Secret chambers
            </h1>
            <p class="text-base text-muted-foreground">
              Spin up a private jam room. Share the link with whoever
              you want to play with — anyone who has it can join,
              nobody else can find it.
            </p>
          </div>
          <button
            phx-click="create_chamber"
            class="w-full rounded-lg border bg-card hover:bg-accent px-6 py-3 text-base font-medium font-display tracking-tight transition-colors cursor-pointer"
          >
            Create a chamber
          </button>
          <p class="text-xs text-muted-foreground">
            If nobody else joins within 5 minutes, the chamber closes
            on its own.
          </p>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
