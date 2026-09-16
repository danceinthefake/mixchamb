defmodule MixchambWeb.ChamberLive.MiniGame do
  @moduledoc """
  Mini-game half of `MixchambWeb.ChamberLive`. Routes stage events
  to the chamber GenServer (which gates host / drawer rules) and
  relays the game's broadcasts back to the client. See
  `features/mini-game.md`.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3]

  # Mini-game: pull the live ephemeral state from the chamber's
  # GenServer. nil outside "minigame" activity — the template's
  # `:if={@minigame_state}` checks stay uniform with poker/retro.
  def load(%{activity: "minigame", slug: slug}) do
    Mixchamb.Chambers.Server.minigame_state(slug)
  end

  def load(_), do: nil

  @doc "Mini-game assigns seeded on mount and on activity switch."
  def mount_assigns(socket, chamber), do: assign(socket, :minigame_state, load(chamber))

  # --- Mini-game events ------------------------------------------
  # Each delegates to the chamber GenServer, which authoritatively
  # gates host/drawer rules and broadcasts. The LV just routes +
  # supplies identity (user_id, alias). See features/mini-game.md.

  def handle_event("minigame_select_game", %{"game" => game}, socket)
      when is_binary(game) do
    Mixchamb.Chambers.Server.minigame_select_game(
      socket.assigns.chamber_slug,
      socket.assigns.current_user.id,
      game
    )

    {:noreply, socket}
  end

  def handle_event("minigame_set_config", %{"config" => config}, socket)
      when is_map(config) do
    Mixchamb.Chambers.Server.minigame_set_config(
      socket.assigns.chamber_slug,
      socket.assigns.current_user.id,
      config
    )

    {:noreply, socket}
  end

  def handle_event("minigame_start", _params, socket) do
    player_ids =
      Enum.map(MixchambWeb.ChamberLive.participants(socket.assigns.presences), & &1.user_id)

    Mixchamb.Chambers.Server.minigame_start(
      socket.assigns.chamber_slug,
      socket.assigns.current_user.id,
      player_ids
    )

    {:noreply, socket}
  end

  # Play-again and End both reset to a fresh lobby in v1 (the lobby
  # is the "no game running" screen). Separate events keep the wire
  # honest if they ever diverge.
  def handle_event(event, _params, socket)
      when event in ["minigame_play_again", "minigame_end"] do
    Mixchamb.Chambers.Server.minigame_to_lobby(
      socket.assigns.chamber_slug,
      socket.assigns.current_user.id
    )

    {:noreply, socket}
  end

  def handle_event("minigame_choose_word", %{"word" => word}, socket)
      when is_binary(word) do
    Mixchamb.Chambers.Server.minigame_choose_word(
      socket.assigns.chamber_slug,
      socket.assigns.current_user.id,
      word
    )

    {:noreply, socket}
  end

  def handle_event("minigame_guess", %{"text" => text}, socket) when is_binary(text) do
    user = socket.assigns.current_user

    Mixchamb.Chambers.Server.minigame_guess(
      socket.assigns.chamber_slug,
      user.id,
      user.alias || user.display_name,
      text
    )

    {:noreply, socket}
  end

  def handle_event("minigame_skip", _params, socket) do
    Mixchamb.Chambers.Server.minigame_skip(
      socket.assigns.chamber_slug,
      socket.assigns.current_user.id
    )

    {:noreply, socket}
  end

  def handle_event("minigame_next", _params, socket) do
    Mixchamb.Chambers.Server.minigame_next(
      socket.assigns.chamber_slug,
      socket.assigns.current_user.id
    )

    {:noreply, socket}
  end

  # Gartic Phone: submit this step's entry (text or drawing strokes).
  def handle_event("minigame_submit", payload, socket) when is_map(payload) do
    Mixchamb.Chambers.Server.minigame_submit(
      socket.assigns.chamber_slug,
      socket.assigns.current_user.id,
      Map.drop(payload, ["_target"])
    )

    {:noreply, socket}
  end

  # Gartic Phone: host advances the album.
  def handle_event("minigame_album_next", _params, socket) do
    Mixchamb.Chambers.Server.minigame_album_next(
      socket.assigns.chamber_slug,
      socket.assigns.current_user.id
    )

    {:noreply, socket}
  end

  # Drawing relay. The GenServer enforces drawer-only / mid-turn;
  # these high-frequency events never reload the per-user view.
  def handle_event("minigame_stroke", payload, socket) when is_map(payload) do
    Mixchamb.Chambers.Server.minigame_stroke(
      socket.assigns.chamber_slug,
      socket.assigns.current_user.id,
      payload
    )

    {:noreply, socket}
  end

  def handle_event("minigame_stroke_end", stroke, socket) when is_map(stroke) do
    Mixchamb.Chambers.Server.minigame_stroke_end(
      socket.assigns.chamber_slug,
      socket.assigns.current_user.id,
      stroke
    )

    {:noreply, socket}
  end

  def handle_event("minigame_undo", _params, socket) do
    Mixchamb.Chambers.Server.minigame_undo(
      socket.assigns.chamber_slug,
      socket.assigns.current_user.id
    )

    {:noreply, socket}
  end

  def handle_event("minigame_clear", _params, socket) do
    Mixchamb.Chambers.Server.minigame_clear(
      socket.assigns.chamber_slug,
      socket.assigns.current_user.id
    )

    {:noreply, socket}
  end

  # Low-frequency game event: reload the per-user view (scoreboard,
  # phase, blanks, drawer, deadline, stroke snapshot).
  def handle_info({:minigame, :changed}, socket) do
    {:noreply, assign(socket, :minigame_state, load(socket.assigns.chamber))}
  end

  # Transient guess-feed line — pushed straight to the client, never
  # part of reloadable state (spec §4).
  def handle_info({:minigame_feed, payload}, socket) do
    {:noreply, push_event(socket, "minigame_feed", payload)}
  end

  # Drawing relay — strokes / undo / clear from the drawer. Pushed to
  # every client; the canvas skips events whose `from` is itself (the
  # drawer already rendered locally, same self-skip as note replay).
  def handle_info({:minigame_relay, kind, payload}, socket) do
    {:noreply,
     push_event(socket, "minigame_relay", %{kind: Atom.to_string(kind), payload: payload})}
  end

  # so the drawer sees the secret word while guessers see only
  # blanks (spec §1). nil outside minigame mode.
  def view(nil, _user_id), do: nil

  def view(%Mixchamb.MiniGame.State{} = state, user_id) do
    Mixchamb.MiniGame.Registry.module(state.game).view(state, user_id)
  end
end
