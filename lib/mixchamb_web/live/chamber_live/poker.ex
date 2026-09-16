defmodule MixchambWeb.ChamberLive.Poker do
  @moduledoc """
  Planning-poker half of `MixchambWeb.ChamberLive`. Events from
  PokerBoard.vue route here; every mutation goes through the
  chamber GenServer, which broadcasts, and `handle_info/2` re-pulls
  the authoritative session.
  """

  import Phoenix.Component, only: [assign: 3]

  # Pull the current PokerSession off the chamber's GenServer. Returns
  # `nil` for non-poker chambers — the assign is still set so the
  # template can render `:if={@poker_session}` checks uniformly.
  def load(%{activity: "poker", slug: slug}) do
    Mixchamb.Chambers.Server.poker_state(slug)
  end

  def load(_), do: nil

  @doc "Poker assigns seeded on mount and on activity switch."
  def mount_assigns(socket, chamber), do: assign(socket, :poker_session, load(chamber))

  # ── Poker events from the Vue island ─────────────────────────────
  # Each one delegates to the chamber's GenServer; the server
  # broadcasts on success and every client (including this one)
  # picks the change up via the `{:poker, _, _}` handle_info below.

  def handle_event("poker_vote", %{"card" => card}, socket) when is_binary(card) do
    Mixchamb.Chambers.Server.poker_vote(
      socket.assigns.chamber_slug,
      socket.assigns.current_user.id,
      card
    )

    {:noreply, socket}
  end

  def handle_event("poker_withdraw_vote", _params, socket) do
    Mixchamb.Chambers.Server.poker_withdraw_vote(
      socket.assigns.chamber_slug,
      socket.assigns.current_user.id
    )

    {:noreply, socket}
  end

  def handle_event("poker_reveal", _params, socket) do
    if socket.assigns.is_host do
      Mixchamb.Chambers.Server.poker_reveal(socket.assigns.chamber_slug)
    end

    {:noreply, socket}
  end

  def handle_event("poker_revote", _params, socket) do
    if socket.assigns.is_host do
      Mixchamb.Chambers.Server.poker_revote(socket.assigns.chamber_slug)
    end

    {:noreply, socket}
  end

  def handle_event("poker_next_round", params, socket) do
    if socket.assigns.is_host do
      story = Map.get(params, "story")
      Mixchamb.Chambers.Server.poker_next_round(socket.assigns.chamber_slug, story)
    end

    {:noreply, socket}
  end

  def handle_event("poker_set_story", %{"story" => story}, socket) do
    if socket.assigns.is_host do
      Mixchamb.Chambers.Server.poker_set_story(socket.assigns.chamber_slug, story)
    end

    {:noreply, socket}
  end

  def handle_event("poker_set_deck", %{"deck" => deck}, socket) when is_binary(deck) do
    if socket.assigns.is_host do
      Mixchamb.Chambers.Server.poker_set_deck(
        socket.assigns.chamber_slug,
        String.to_existing_atom(deck)
      )
    end

    {:noreply, socket}
  end

  # Host pastes a backlog into the queue editor. Payload is a list
  # of strings; PokerSession trims + caps. Non-host attempts are
  # silently dropped to keep the surface idempotent — the UI hides
  # the editor for non-hosts already, this is belt-and-braces for
  # hand-crafted phx events.
  def handle_event("poker_set_queue", %{"queue" => queue}, socket) when is_list(queue) do
    if socket.assigns.is_host do
      Mixchamb.Chambers.Server.poker_set_queue(socket.assigns.chamber_slug, queue)
    end

    {:noreply, socket}
  end

  # Any poker broadcast (vote_cast / withdrawn / revealed / cleared /
  # story_changed / deck_changed) just re-pulls the authoritative
  # session from the GenServer. One extra cast per broadcast — cheap,
  # and avoids having to track per-event diffs against a stale local
  # copy.
  def handle_info({:poker, _evt, _payload}, socket) do
    {:noreply, assign(socket, :poker_session, load(socket.assigns.chamber))}
  end

  def handle_info({:poker, _evt, _a, _b, _c}, socket) do
    {:noreply, assign(socket, :poker_session, load(socket.assigns.chamber))}
  end

  # ── Wire shapes ──────────────────────────────────────────────────

  # Shape the PokerSession into the JSON-safe map that Chamber.vue
  # (and PokerBoard.vue) consume. Filters vote values during `:voting`
  # so only the current user's own card is sent to the client; the
  # rest of the room sees just a "this user has voted" signal until
  # the host reveals. On `:revealed`, every value is exposed.
  def view(nil, _user_id), do: nil

  def view(session, user_id) do
    voted_user_ids = session.votes |> Map.keys() |> Enum.sort()
    my_vote = Map.get(session.votes, user_id)

    %{
      status: Atom.to_string(session.status),
      deck: Atom.to_string(session.deck),
      cards: Mixchamb.Chambers.PokerSession.cards_for(session.deck),
      story: session.story,
      round: session.round,
      my_vote: my_vote,
      voted_user_ids: voted_user_ids,
      votes: if(session.status == :revealed, do: session.votes, else: %{}),
      history: Enum.map(session.history, &history_view/1),
      queue: session.queue
    }
  end

  # Shape history entries for the wire. Strip user_ids — the
  # RoundHistory panel only renders the verdict + count, not a
  # per-user breakdown (that's RevealPanel's job, and only for
  # the live round). Snapshot the deck's card order so the
  # client can compute the "close" verdict correctly even if
  # the deck was switched between rounds.
  def history_view(entry) do
    %{
      round: entry.round,
      story: entry.story,
      deck: Atom.to_string(entry.deck),
      cards: Mixchamb.Chambers.PokerSession.cards_for(entry.deck),
      values: Map.values(entry.votes)
    }
  end
end
