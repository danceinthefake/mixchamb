defmodule MixchambWeb.ChamberLive.Retro do
  @moduledoc """
  Retrospective half of `MixchambWeb.ChamberLive`. Persistent
  session state lives in the DB (reloaded on every broadcast);
  vote tallies / my-votes / discussing-card are ephemeral GenServer
  state mirrored into assigns here.
  """

  import Phoenix.Component, only: [assign: 3]

  # Same shape for retro: pull the current non-archived session
  # for this chamber from the DB (with columns/cards/actions
  # preloaded). Returns `nil` outside retro mode OR inside retro
  # before the host has started a session.
  def load_session(%{activity: "retro", id: chamber_id}) do
    case Mixchamb.Retro.current_session(chamber_id) do
      nil -> nil
      session -> Mixchamb.Retro.load_session(session.id)
    end
  end

  def load_session(_), do: nil

  # Past archived retro sessions for this chamber, newest-first.
  # Returns [] outside retro mode so the template can render the
  # disclosure unconditionally without an `:if`.
  def load_past(%{activity: "retro", id: chamber_id}) do
    Mixchamb.Retro.list_archived_sessions(chamber_id)
  end

  def load_past(_), do: []

  @doc "Retro assigns seeded on mount."
  def mount_assigns(socket, chamber, user) do
    socket
    |> reload(chamber)
    # Live vote tallies during :voting — kept here (not in
    # retro_session, which only carries DB-persisted state) so
    # the LV diff is cheap on every vote broadcast. Reset on
    # phase exit. Same for my_votes (per-user vote set).
    |> assign(:retro_tallies, %{})
    |> assign(:retro_my_votes, MapSet.new())
    # Host's highlighted card during :discuss. Surfaces the
    # discussing-card focus from the GenServer ephemeral state.
    # nil when nothing focused. Reset on phase exit.
    |> assign(:retro_discussing_card_id, nil)
    |> assign(:retro_discussed, [])
    # Host's phase timer, absolute ms deadline (nil = none).
    |> assign(:retro_timer_deadline, nil)
    |> assign(:retro_timer_auto, false)
    # Seed all three ephemeral assigns from the GenServer for
    # late joiners / refreshes — without this, joining a chamber
    # mid-:voting shows 0/3 votes spent and no live tallies until
    # the next vote event.
    |> seed_ephemeral(chamber, user)
  end

  @doc "Re-pull session + archive list (activity switch / phase change)."
  def reload(socket, chamber) do
    session = load_session(chamber)

    socket
    |> assign(:retro_session, session)
    |> assign(:past_retros, load_past(chamber))
    # Open items from the team's earlier retros (spec §13). [] when
    # there's no session or no team.
    |> assign(:retro_previous_actions, previous_actions(session))
  end

  defp previous_actions(nil), do: []
  defp previous_actions(session), do: Mixchamb.Retro.open_previous_action_items(session)

  # Pulls the live EphemeralState off the chamber GenServer and
  # seeds retro_tallies / retro_my_votes / retro_discussing_card_id
  # so a fresh mount (late joiner, refresh, server-side LV
  # reconnect) sees the same in-flight state as everyone else.
  # No-op outside retro activity or before a session is started.
  defp seed_ephemeral(socket, %{activity: "retro", slug: slug}, %{id: user_id}) do
    case Mixchamb.Chambers.Server.retro_state(slug) do
      nil ->
        socket

      %_{} = rs ->
        socket
        |> assign(:retro_tallies, Mixchamb.Retro.EphemeralState.tally(rs))
        |> assign(:retro_my_votes, Map.get(rs.votes, user_id, MapSet.new()))
        |> assign(:retro_discussing_card_id, rs.discussing_card_id)
        |> assign(:retro_discussed, MapSet.to_list(rs.discussed))
        |> assign(:retro_timer_deadline, rs.timer_deadline)
        |> assign(:retro_timer_auto, rs.auto_advance)
    end
  end

  defp seed_ephemeral(socket, _, _), do: socket

  # --- Retro events from RetroBoard.vue ---------------------------
  # Host-only: start_session / set_title / set_voting_enabled /
  # rename_column / advance_phase / set_discussing. Anyone-in-chamber:
  # add_card / update_card / delete_card / vote / withdraw_vote /
  # add_action_item / update_action_item / delete_action_item.
  # Server-side gates are authoritative (Chambers.Server checks
  # state.hosts); the @is_host check here is fast-path UI only.

  def handle_event("retro_start_session", _params, socket) do
    if socket.assigns.is_host do
      Mixchamb.Chambers.Server.retro_start_session(
        socket.assigns.chamber_slug,
        socket.assigns.current_user.id
      )
    end

    {:noreply, socket}
  end

  def handle_event("retro_set_title", %{"title" => title}, socket) when is_binary(title) do
    if socket.assigns.is_host do
      Mixchamb.Chambers.Server.retro_set_title(
        socket.assigns.chamber_slug,
        socket.assigns.current_user.id,
        title
      )
    end

    {:noreply, socket}
  end

  def handle_event("retro_set_timer", %{"seconds" => seconds} = params, socket)
      when is_nil(seconds) or is_integer(seconds) do
    if socket.assigns.is_host do
      Mixchamb.Chambers.Server.retro_set_timer(
        socket.assigns.chamber_slug,
        socket.assigns.current_user.id,
        seconds,
        Map.get(params, "auto_advance") == true
      )
    end

    {:noreply, socket}
  end

  def handle_event("retro_set_team", %{"team" => name}, socket) when is_binary(name) do
    if socket.assigns.is_host do
      Mixchamb.Chambers.Server.retro_set_team(
        socket.assigns.chamber_slug,
        socket.assigns.current_user.id,
        name
      )
    end

    {:noreply, socket}
  end

  def handle_event("retro_set_voting_enabled", %{"enabled" => enabled}, socket)
      when is_boolean(enabled) do
    if socket.assigns.is_host do
      Mixchamb.Chambers.Server.retro_set_voting_enabled(
        socket.assigns.chamber_slug,
        socket.assigns.current_user.id,
        enabled
      )
    end

    {:noreply, socket}
  end

  def handle_event("retro_set_brainstorm_visible", %{"visible" => visible}, socket)
      when is_boolean(visible) do
    if socket.assigns.is_host do
      Mixchamb.Chambers.Server.retro_set_brainstorm_visible(
        socket.assigns.chamber_slug,
        socket.assigns.current_user.id,
        visible
      )
    end

    {:noreply, socket}
  end

  def handle_event(
        "retro_rename_column",
        %{"column_id" => column_id, "name" => name},
        socket
      )
      when is_binary(column_id) and is_binary(name) do
    if socket.assigns.is_host do
      Mixchamb.Chambers.Server.retro_rename_column(
        socket.assigns.chamber_slug,
        socket.assigns.current_user.id,
        column_id,
        name
      )
    end

    {:noreply, socket}
  end

  def handle_event("retro_advance_phase", _params, socket) do
    if socket.assigns.is_host do
      Mixchamb.Chambers.Server.retro_advance_phase(
        socket.assigns.chamber_slug,
        socket.assigns.current_user.id
      )
    end

    {:noreply, socket}
  end

  def handle_event(
        "retro_add_card",
        %{"column_id" => column_id, "body" => body},
        socket
      )
      when is_binary(column_id) and is_binary(body) do
    user = socket.assigns.current_user
    # Snapshot both halves of the identity at card-create time
    # (spec §3 + the "alias is additive on top of display_name"
    # convention). When no alias is set, author_alias falls back
    # to display_name so the card always has a non-nil primary
    # label; author_display_name carries the noun-adj-NN handle
    # separately for the two-piece render.
    author_alias = user.alias || user.display_name

    Mixchamb.Chambers.Server.retro_add_card(
      socket.assigns.chamber_slug,
      user.id,
      column_id,
      body,
      author_alias,
      user.display_name
    )

    {:noreply, socket}
  end

  def handle_event(
        "retro_update_card",
        %{"card_id" => card_id, "body" => body},
        socket
      )
      when is_binary(card_id) and is_binary(body) do
    Mixchamb.Chambers.Server.retro_update_card(
      socket.assigns.chamber_slug,
      socket.assigns.current_user.id,
      card_id,
      body
    )

    {:noreply, socket}
  end

  def handle_event("retro_merge_card", %{"source_id" => source, "target_id" => target}, socket)
      when is_binary(source) and is_binary(target) do
    if socket.assigns.is_host do
      Mixchamb.Chambers.Server.retro_merge_card(
        socket.assigns.chamber_slug,
        socket.assigns.current_user.id,
        source,
        target
      )
    end

    {:noreply, socket}
  end

  def handle_event("retro_unmerge_card", %{"card_id" => card_id}, socket)
      when is_binary(card_id) do
    if socket.assigns.is_host do
      Mixchamb.Chambers.Server.retro_unmerge_card(
        socket.assigns.chamber_slug,
        socket.assigns.current_user.id,
        card_id
      )
    end

    {:noreply, socket}
  end

  def handle_event("retro_delete_card", %{"card_id" => card_id}, socket)
      when is_binary(card_id) do
    Mixchamb.Chambers.Server.retro_delete_card(
      socket.assigns.chamber_slug,
      socket.assigns.current_user.id,
      card_id
    )

    {:noreply, socket}
  end

  def handle_event("retro_vote", %{"card_id" => card_id}, socket) when is_binary(card_id) do
    Mixchamb.Chambers.Server.retro_vote(
      socket.assigns.chamber_slug,
      socket.assigns.current_user.id,
      card_id
    )

    {:noreply, socket}
  end

  def handle_event("retro_withdraw_vote", %{"card_id" => card_id}, socket)
      when is_binary(card_id) do
    Mixchamb.Chambers.Server.retro_withdraw_vote(
      socket.assigns.chamber_slug,
      socket.assigns.current_user.id,
      card_id
    )

    {:noreply, socket}
  end

  def handle_event("retro_set_discussing", params, socket) do
    card_id = Map.get(params, "card_id")

    if socket.assigns.is_host do
      Mixchamb.Chambers.Server.retro_set_discussing(
        socket.assigns.chamber_slug,
        socket.assigns.current_user.id,
        card_id
      )
    end

    {:noreply, socket}
  end

  def handle_event("retro_add_action_item", params, socket) do
    user = socket.assigns.current_user

    attrs =
      params
      |> Map.take(["body", "source_card_id", "assignee_alias", "due_date"])
      |> Map.new(fn {k, v} -> {String.to_atom(k), v} end)
      |> Map.put(:created_by_user_id, user.id)

    Mixchamb.Chambers.Server.retro_add_action_item(socket.assigns.chamber_slug, attrs)

    {:noreply, socket}
  end

  def handle_event(
        "retro_update_action_item",
        %{"action_id" => action_id} = params,
        socket
      )
      when is_binary(action_id) do
    attrs =
      params
      |> Map.take(["body", "assignee_alias", "due_date", "completed"])
      |> Map.new(fn {k, v} -> {String.to_atom(k), v} end)

    Mixchamb.Chambers.Server.retro_update_action_item(
      socket.assigns.chamber_slug,
      action_id,
      attrs
    )

    {:noreply, socket}
  end

  # Retro → poker handoff (spec §15): flip the chamber to poker with
  # the retro's open action items queued as stories. Host-gated like
  # every other retro host action; the three casts land in the same
  # GenServer mailbox, so set_activity is applied before the queue.
  def handle_event("retro_estimate_in_poker", _params, socket) do
    %{chamber: chamber, retro_session: session, is_host: is_host} = socket.assigns

    stories =
      if session, do: for(a <- session.action_items, not a.completed, do: a.body), else: []

    with true <- is_host and stories != [],
         {:ok, _} <- Mixchamb.Chambers.set_activity(chamber, "poker") do
      [first | rest] = stories
      Mixchamb.Chambers.Server.poker_set_story(chamber.slug, first)
      Mixchamb.Chambers.Server.poker_set_queue(chamber.slug, rest)
    end

    {:noreply, socket}
  end

  def handle_event("retro_carry_over_action", %{"action_id" => action_id}, socket)
      when is_binary(action_id) do
    Mixchamb.Chambers.Server.retro_carry_over_action(
      socket.assigns.chamber_slug,
      socket.assigns.current_user.id,
      action_id
    )

    {:noreply, socket}
  end

  def handle_event("retro_complete_previous_action", %{"action_id" => action_id}, socket)
      when is_binary(action_id) do
    Mixchamb.Chambers.Server.retro_complete_previous_action(
      socket.assigns.chamber_slug,
      action_id
    )

    {:noreply, socket}
  end

  def handle_event("retro_delete_action_item", %{"action_id" => action_id}, socket)
      when is_binary(action_id) do
    Mixchamb.Chambers.Server.retro_delete_action_item(socket.assigns.chamber_slug, action_id)
    {:noreply, socket}
  end

  def handle_event(
        "retro_toggle_reaction",
        %{"card_id" => card_id, "emoji" => emoji},
        socket
      )
      when is_binary(card_id) and is_binary(emoji) do
    Mixchamb.Chambers.Server.retro_toggle_reaction(
      socket.assigns.chamber_slug,
      socket.assigns.current_user.id,
      card_id,
      emoji
    )

    {:noreply, socket}
  end

  def handle_event(
        "retro_add_comment",
        %{"card_id" => card_id, "body" => body},
        socket
      )
      when is_binary(card_id) and is_binary(body) do
    user = socket.assigns.current_user
    author_alias = user.alias || user.display_name

    Mixchamb.Chambers.Server.retro_add_comment(
      socket.assigns.chamber_slug,
      user.id,
      card_id,
      body,
      author_alias,
      user.display_name
    )

    {:noreply, socket}
  end

  def handle_event(
        "retro_update_comment",
        %{"comment_id" => comment_id, "body" => body},
        socket
      )
      when is_binary(comment_id) and is_binary(body) do
    Mixchamb.Chambers.Server.retro_update_comment(
      socket.assigns.chamber_slug,
      socket.assigns.current_user.id,
      comment_id,
      body
    )

    {:noreply, socket}
  end

  def handle_event("retro_delete_comment", %{"comment_id" => comment_id}, socket)
      when is_binary(comment_id) do
    Mixchamb.Chambers.Server.retro_delete_comment(
      socket.assigns.chamber_slug,
      socket.assigns.current_user.id,
      comment_id
    )

    {:noreply, socket}
  end

  # Retro broadcasts — reload the full session from DB for the
  # state-changing ones (card add/edit/delete, action add/edit/delete,
  # phase change, voting toggle, title/column rename, session start).
  # Vote events also reload (so the LV's view of vote tallies stays
  # in sync); the per-card vote counts are denormalised on cards
  # post-materialisation, but mid-voting we don't surface live tallies
  # from this stub anyway. Wire shapes:
  #   {:retro, :evt, payload}          (3-tuple)
  #   {:retro, :evt, a, b}             (4-tuple — card_edited, column_renamed, vote_cast pre-tallies)
  #   {:retro, :evt, user_id, card_id, tallies}  (5-tuple — vote_cast / vote_withdrawn)
  def handle_info({:retro, :phase_changed, new_phase}, socket) do
    chamber = socket.assigns.chamber

    socket =
      socket
      |> assign(:retro_session, load_session(chamber))
      # Reset vote tallies + my-votes + discussing focus on every
      # phase change. Entering :voting starts at zero; exiting
      # :voting drops the now-stale ephemeral signals (the
      # materialised counts come back on the reloaded session).
      |> assign(:retro_tallies, %{})
      |> assign(:retro_my_votes, MapSet.new())
      |> assign(:retro_discussing_card_id, nil)
      |> assign(:retro_discussed, [])
      |> assign(:retro_timer_deadline, nil)
      |> assign(:retro_timer_auto, false)

    # Archive transition produces a new row in past_retros — reload
    # the disclosure list. Other transitions don't touch that list.
    socket =
      if new_phase == :archived do
        assign(socket, :past_retros, load_past(chamber))
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_info({:retro, :vote_cast, user_id, card_id, tallies}, socket) do
    my_votes =
      if user_id == socket.assigns.current_user.id do
        MapSet.put(socket.assigns.retro_my_votes, card_id)
      else
        socket.assigns.retro_my_votes
      end

    {:noreply,
     socket
     |> assign(:retro_tallies, tallies)
     |> assign(:retro_my_votes, my_votes)}
  end

  def handle_info({:retro, :vote_withdrawn, user_id, card_id, tallies}, socket) do
    my_votes =
      if user_id == socket.assigns.current_user.id do
        MapSet.delete(socket.assigns.retro_my_votes, card_id)
      else
        socket.assigns.retro_my_votes
      end

    {:noreply,
     socket
     |> assign(:retro_tallies, tallies)
     |> assign(:retro_my_votes, my_votes)}
  end

  # Discussing-focus is ephemeral GenServer state, not in the
  # session DB row — handle it before the catch-all so we don't
  # incur a session reload for what's just a card-id swap.
  def handle_info({:retro, :discussing, card_id_or_nil, discussed}, socket) do
    {:noreply,
     socket
     |> assign(:retro_discussing_card_id, card_id_or_nil)
     |> assign(:retro_discussed, discussed)}
  end

  def handle_info({:retro, :timer, %{deadline: deadline, auto_advance: auto}}, socket) do
    {:noreply,
     socket
     |> assign(:retro_timer_deadline, deadline)
     |> assign(:retro_timer_auto, auto)}
  end

  # Catch-all retro broadcasts (card/action add/edit/delete, title,
  # column rename, voting toggle, session start) all just reload
  # the session. Cheap, avoids per-event patching against a stale
  # local copy.
  def handle_info({:retro, _evt, _payload}, socket) do
    {:noreply, reload(socket, socket.assigns.chamber)}
  end

  def handle_info({:retro, _evt, _a, _b}, socket) do
    {:noreply, assign(socket, :retro_session, load_session(socket.assigns.chamber))}
  end

  def handle_info({:retro, _evt, _a, _b, _c}, socket) do
    {:noreply, assign(socket, :retro_session, load_session(socket.assigns.chamber))}
  end

  # :reaction_toggled is the only 6-tuple broadcast (card_id +
  # user_id + emoji + :added|:removed). Reloading the session
  # is heavier than a per-card patch would be, but reaction
  # volume is low (one click per intent) so the cost is fine
  # and keeps the receive-side simple.
  def handle_info({:retro, _evt, _a, _b, _c, _d}, socket) do
    {:noreply, assign(socket, :retro_session, load_session(socket.assigns.chamber))}
  end

  # ── Wire shapes ──────────────────────────────────────────────────

  # Shape the loaded RetroSession (with its columns/cards/actions
  # preloads) into a JSON-safe map for Chamber.vue / RetroBoard.vue.
  # Strips Ecto metadata and snakes-into the wire shape RetroBoard
  # expects (see assets/vue/activities/retro/RetroBoard.vue's
  # `RetroSession` type). No per-user vote filtering at this layer
  # — votes are ephemeral in the GenServer; vote_count on each
  # card is the only persisted signal.
  def view(nil), do: nil

  def view(session) do
    %{
      id: session.id,
      title: session.title,
      status: session.status,
      voting_enabled: session.voting_enabled,
      brainstorm_visible: session.brainstorm_visible,
      team: session.team && %{slug: session.team.slug, name: session.team.name},
      columns:
        Enum.map(session.columns, fn col ->
          %{id: col.id, name: col.name, position: col.position}
        end),
      cards: cards_view(session.cards),
      action_items:
        Enum.map(session.action_items, fn action ->
          %{
            id: action.id,
            source_card_id: action.source_card_id,
            body: action.body,
            assignee_alias: action.assignee_alias,
            # Date → ISO string for the wire. live_vue's JSON
            # encoder doesn't know how to serialise %Date{}.
            due_date: action.due_date && Date.to_iso8601(action.due_date),
            completed: action.completed
          }
        end)
    }
  end

  # Merged cards (spec §20) fold into their target: the target card
  # carries `merged` (the folded bodies + authors) and the union of
  # everyone's reactions / comments; the folded rows themselves
  # don't appear as board cards.
  defp cards_view(cards) do
    children = Enum.group_by(cards, & &1.merged_into_card_id)

    cards
    |> Enum.reject(& &1.merged_into_card_id)
    |> Enum.map(fn card ->
      folded = Map.get(children, card.id, [])
      all = [card | folded]

      %{
        id: card.id,
        retro_column_id: card.retro_column_id,
        body: card.body,
        author_user_id: card.author_user_id,
        author_alias: card.author_alias,
        author_display_name: card.author_display_name,
        vote_count: card.vote_count,
        merged:
          Enum.map(folded, fn c ->
            %{
              id: c.id,
              body: c.body,
              author_user_id: c.author_user_id,
              author_alias: c.author_alias,
              author_display_name: c.author_display_name
            }
          end),
        reactions:
          all
          |> Enum.flat_map(& &1.reactions)
          |> Enum.map(&%{user_id: &1.user_id, emoji: &1.emoji})
          |> Enum.uniq_by(&{&1.user_id, &1.emoji}),
        comments:
          all
          |> Enum.flat_map(& &1.comments)
          |> Enum.map(fn co ->
            %{
              id: co.id,
              body: co.body,
              author_user_id: co.author_user_id,
              author_alias: co.author_alias,
              author_display_name: co.author_display_name
            }
          end)
      }
    end)
  end

  @doc "Wire shape for the carry-over panel (spec §13)."
  def previous_actions_view(items) do
    Enum.map(items, fn a ->
      %{
        id: a.id,
        body: a.body,
        assignee_alias: a.assignee_alias,
        due_date: a.due_date && Date.to_iso8601(a.due_date),
        from_title: a.session.title,
        from_archived_at: a.session.archived_at
      }
    end)
  end

  # Slim wire shape for the most-recent archived retro in this
  # chamber. RetroBoard renders a "Copy share link" notice in
  # its empty state pointing at this. Returns nil when nothing's
  # been archived yet.
  def last_archived([]), do: nil

  def last_archived([latest | _]) do
    %{
      id: latest.id,
      title: latest.title,
      archived_at: latest.archived_at
    }
  end

  # Just the display labels (alias_or_name) for the current
  # participants, used by retro's assignee-input autocomplete
  # (spec §6). Sorted by joined_at for a stable order; deduped
  # in case anyone joined twice from different tabs.
  def participant_aliases(presences) do
    presences
    |> Enum.map(fn {_user_id, %{metas: [meta | _]}} ->
      {meta.alias || meta.display_name, meta.joined_at}
    end)
    |> Enum.sort_by(fn {_label, joined_at} -> joined_at end)
    |> Enum.map(fn {label, _} -> label end)
    |> Enum.uniq()
  end
end
