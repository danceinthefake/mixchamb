defmodule Mixchamb.Retro do
  @moduledoc """
  The Retrospective context. Persistent ops only — sessions,
  columns, cards, action items. Ephemeral state (vote map +
  discussing-card focus) lives in `Mixchamb.Chambers.Server` via
  `Mixchamb.Retro.EphemeralState`.

  Design: `features/retrospective.md`. Phase transitions are
  validated here (the persisted `status` field is the source of
  truth); the GenServer mirror is for fast access only.
  """

  import Ecto.Query
  alias Mixchamb.Repo

  alias Mixchamb.Retro.{
    RetroSession,
    RetroColumn,
    RetroCard,
    RetroActionItem,
    RetroCardReaction,
    RetroCardComment,
    Team
  }

  # ---------------------------------------------------------------
  # Sessions
  # ---------------------------------------------------------------

  @doc """
  Start a new retro session for `chamber_id`, seeded with the
  4 default columns. Refuses if there's already a non-archived
  session for this chamber.
  """
  def start_session(chamber_id, attrs \\ %{}) when is_binary(chamber_id) do
    case current_session(chamber_id) do
      nil ->
        # Inherit the team from this chamber's previous retro so a
        # recurring chamber doesn't make the host retype the slug
        # every sprint. Explicit attrs still win.
        attrs =
          attrs
          |> Map.put(:chamber_id, chamber_id)
          |> Map.put_new(:team_id, latest_team_id(chamber_id))

        Repo.transaction(fn ->
          case %RetroSession{}
               |> RetroSession.creation_changeset(attrs)
               |> Repo.insert() do
            {:ok, session} ->
              seed_default_columns!(session)
              load_session!(session.id)

            {:error, changeset} ->
              Repo.rollback(changeset)
          end
        end)

      _existing ->
        {:error, :session_already_active}
    end
  end

  defp latest_team_id(chamber_id) do
    Repo.one(
      from s in RetroSession,
        where: s.chamber_id == ^chamber_id and not is_nil(s.team_id),
        order_by: [desc: s.inserted_at],
        limit: 1,
        select: s.team_id
    )
  end

  defp seed_default_columns!(%RetroSession{id: session_id}) do
    RetroColumn.default_names()
    |> Enum.with_index()
    |> Enum.each(fn {name, position} ->
      %RetroColumn{}
      |> RetroColumn.creation_changeset(%{
        retro_session_id: session_id,
        name: name,
        position: position
      })
      |> Repo.insert!()
    end)
  end

  @doc "Returns the non-archived session for `chamber_id`, or nil."
  def current_session(chamber_id) when is_binary(chamber_id) do
    Repo.one(
      from s in RetroSession,
        where: s.chamber_id == ^chamber_id and s.status != "archived",
        order_by: [desc: s.inserted_at],
        limit: 1
    )
  end

  @doc "Load a session by id with columns + cards + action items preloaded."
  def load_session(session_id) when is_binary(session_id) do
    Repo.get(RetroSession, session_id) |> load_associations()
  end

  def load_session!(session_id) when is_binary(session_id) do
    Repo.get!(RetroSession, session_id) |> load_associations()
  end

  @doc """
  Load an archived session by id (the permanent
  `/archives/retros/:id` view).
  Returns `nil` if no row exists OR if the row exists but isn't
  archived — live retros are scoped to their chamber's URL and
  shouldn't leak via the public retro permalink. Preloads
  columns / cards / actions so the view renders in one query
  pass.
  """
  def get_archived_by_id(session_id) when is_binary(session_id) do
    case load_session(session_id) do
      %RetroSession{status: "archived"} = session -> session
      _ -> nil
    end
  end

  defp load_associations(nil), do: nil

  defp load_associations(%RetroSession{} = session) do
    Repo.preload(session,
      team: [],
      columns: from(c in RetroColumn, order_by: [asc: c.position]),
      cards:
        {from(c in RetroCard, order_by: [asc: c.inserted_at]),
         [
           reactions: from(r in RetroCardReaction, order_by: [asc: r.inserted_at]),
           comments: from(co in RetroCardComment, order_by: [asc: co.inserted_at])
         ]},
      action_items: from(a in RetroActionItem, order_by: [asc: a.inserted_at])
    )
  end

  @doc """
  List archived retro sessions for a chamber, newest-first.
  Drives the past-retros disclosure in chamber_live.ex.
  """
  def list_archived_sessions(chamber_id) when is_binary(chamber_id) do
    Repo.all(
      from s in RetroSession,
        where: s.chamber_id == ^chamber_id and s.status == "archived",
        # Tiebreak on inserted_at desc — archived_at is truncated
        # to second precision, so two sessions archived in the
        # same second would otherwise order arbitrarily.
        order_by: [desc: s.archived_at, desc: s.inserted_at]
    )
  end

  # ---------------------------------------------------------------
  # Teams
  # ---------------------------------------------------------------

  @doc "Find a team by its slug (already-normalised or not)."
  def get_team_by_slug(slug) when is_binary(slug) do
    Repo.get_by(Team, slug: Team.slugify(slug))
  end

  @doc """
  Find-or-create a team from the text the host typed. Returns
  `{:ok, nil}` for a blank name (meaning "no team").
  """
  def find_or_create_team(name) when is_binary(name) do
    case Team.slugify(name) do
      "" ->
        {:ok, nil}

      slug ->
        case Repo.get_by(Team, slug: slug) do
          %Team{} = team ->
            {:ok, team}

          nil ->
            # A concurrent insert of the same slug loses the race
            # cleanly: the unique_constraint turns it into a
            # changeset error, and we fall back to the winner.
            case Repo.insert(Team.creation_changeset(%Team{}, %{name: name})) do
              {:ok, team} -> {:ok, team}
              {:error, _} -> {:ok, Repo.get_by!(Team, slug: slug)}
            end
        end
    end
  end

  @doc "Tag `session` with the team named `name` (blank clears it)."
  def set_team(%RetroSession{} = session, name) when is_binary(name) do
    with {:ok, team} <- find_or_create_team(name),
         {:ok, updated} <-
           session
           |> RetroSession.team_changeset(%{team_id: team && team.id})
           |> Repo.update() do
      {:ok, %{updated | team: team}}
    end
  end

  @doc "Archived retros for a team, newest-first. Drives `/t/:slug`."
  def list_team_sessions(team_id) when is_binary(team_id) do
    Repo.all(
      from s in RetroSession,
        where: s.team_id == ^team_id and s.status == "archived",
        order_by: [desc: s.archived_at, desc: s.inserted_at]
    )
  end

  @doc """
  Per-team numbers for `/t/:slug` (spec §18): retros run, cards
  written, action items raised / completed, plus the same three
  counts per archived session keyed by session id. Two GROUP BY
  queries over the team's archived sessions.
  """
  def team_summary(team_id) when is_binary(team_id) do
    cards =
      Repo.all(
        from c in RetroCard,
          join: s in assoc(c, :session),
          where: s.team_id == ^team_id and s.status == "archived",
          group_by: c.retro_session_id,
          select: {c.retro_session_id, count(c.id)}
      )
      |> Map.new()

    actions =
      Repo.all(
        from a in RetroActionItem,
          join: s in assoc(a, :session),
          where: s.team_id == ^team_id and s.status == "archived",
          group_by: a.retro_session_id,
          select:
            {a.retro_session_id,
             {count(a.id), sum(fragment("CASE WHEN ? THEN 1 ELSE 0 END", a.completed))}}
      )
      |> Map.new()

    per_session =
      (Map.keys(cards) ++ Map.keys(actions))
      |> Enum.uniq()
      |> Map.new(fn sid ->
        {total, done} = Map.get(actions, sid, {0, 0})
        {sid, %{cards: Map.get(cards, sid, 0), actions: total, done: done || 0}}
      end)

    totals =
      Enum.reduce(per_session, %{cards: 0, actions: 0, done: 0}, fn {_, m}, acc ->
        %{cards: acc.cards + m.cards, actions: acc.actions + m.actions, done: acc.done + m.done}
      end)

    Map.put(totals, :per_session, per_session)
  end

  @doc "Update the session title. Allowed in any phase."
  def set_title(%RetroSession{} = session, title) do
    session
    |> RetroSession.title_changeset(%{title: title})
    |> Repo.update()
  end

  @doc """
  Toggle voting_enabled. Allowed any time before `:discuss`
  (spec §5). Rejected during `:discuss` or `:archived`.
  """
  def set_voting_enabled(%RetroSession{status: s}, _enabled)
      when s in ["discuss", "archived"] do
    {:error, :voting_locked}
  end

  def set_voting_enabled(%RetroSession{} = session, enabled)
      when is_boolean(enabled) do
    session
    |> RetroSession.voting_enabled_changeset(%{voting_enabled: enabled})
    |> Repo.update()
  end

  @doc """
  Snapshot the originating chamber's slug + title + creator onto
  the retro session, so the archived view stays self-describing
  after chamber reaping NULLs out the chamber_id FK. Called by
  `Chambers.Server` when phase advances to `:archived`.
  """
  def snapshot_chamber_archive(%RetroSession{} = session, %{} = chamber) do
    session
    |> RetroSession.archive_snapshot_changeset(%{
      chamber_slug_snapshot: chamber.slug,
      chamber_title_snapshot: chamber.title,
      creator_user_id: chamber.creator_user_id
    })
    |> Repo.update()
  end

  @doc """
  Toggle brainstorm_visible. Allowed during `:setup` only —
  locked once brainstorm begins so writers who started under one
  visibility model don't get surprised mid-stream.
  """
  def set_brainstorm_visible(%RetroSession{status: "setup"} = session, visible)
      when is_boolean(visible) do
    session
    |> RetroSession.brainstorm_visible_changeset(%{brainstorm_visible: visible})
    |> Repo.update()
  end

  def set_brainstorm_visible(%RetroSession{}, _visible) do
    {:error, :setup_only}
  end

  @doc """
  Advance the phase machine by one step. Returns
  `{:ok, session}` on success or `{:error, reason}` if the
  transition isn't valid from the current phase.

  Transitions are linear:
    :setup -> :brainstorm -> :reveal ->
      (:voting if voting_enabled, else :discuss) ->
      :discuss -> :archived
  """
  def advance_phase(%RetroSession{status: status} = session) do
    next =
      case {status, session.voting_enabled} do
        {"setup", _} -> "brainstorm"
        {"brainstorm", _} -> "reveal"
        {"reveal", true} -> "voting"
        {"reveal", false} -> "discuss"
        {"voting", _} -> "discuss"
        {"discuss", _} -> "archived"
        {"archived", _} -> nil
      end

    case next do
      nil ->
        {:error, :already_archived}

      next_status ->
        attrs = phase_timestamps(status, next_status)

        session
        |> RetroSession.phase_changeset(Map.put(attrs, :status, next_status))
        |> Repo.update()
    end
  end

  defp phase_timestamps("brainstorm", "reveal") do
    %{revealed_at: DateTime.utc_now() |> DateTime.truncate(:second)}
  end

  defp phase_timestamps("discuss", "archived") do
    %{archived_at: DateTime.utc_now() |> DateTime.truncate(:second)}
  end

  defp phase_timestamps(_, _), do: %{}

  @doc """
  Set the phase directly. Used by the voting-disabled-mid-vote
  shortcut (`:voting -> :discuss` triggered by toggle-off
  during voting, per spec §5).
  """
  def set_phase(%RetroSession{} = session, phase) when is_atom(phase) do
    status = Atom.to_string(phase)
    attrs = phase_timestamps(session.status, status)

    session
    |> RetroSession.phase_changeset(Map.put(attrs, :status, status))
    |> Repo.update()
  end

  # ---------------------------------------------------------------
  # Columns
  # ---------------------------------------------------------------

  @doc """
  Rename a column. Allowed only during `:setup` (spec §2 — gates
  to avoid header-vs-content drift once cards exist).
  """
  def rename_column(%RetroColumn{} = column, name, %RetroSession{status: "setup"}) do
    column
    |> RetroColumn.rename_changeset(%{name: name})
    |> Repo.update()
  end

  def rename_column(%RetroColumn{}, _name, %RetroSession{}) do
    {:error, :rename_locked}
  end

  # ---------------------------------------------------------------
  # Cards
  # ---------------------------------------------------------------

  @doc """
  Add a card during `:brainstorm`. `author_user_id` may be nil
  for anonymous-user cards; `author_alias` is required (we
  snapshot it at create-time so display stays stable across
  alias edits).
  """
  def add_card(
        %RetroSession{status: "brainstorm", id: session_id},
        %RetroColumn{id: column_id, retro_session_id: column_session_id},
        attrs
      )
      when session_id == column_session_id do
    %RetroCard{}
    |> RetroCard.creation_changeset(
      Map.merge(attrs, %{
        retro_session_id: session_id,
        retro_column_id: column_id
      })
    )
    |> Repo.insert()
  end

  def add_card(%RetroSession{status: status}, _column, _attrs)
      when status != "brainstorm" do
    {:error, :brainstorm_only}
  end

  def add_card(_, _, _), do: {:error, :column_session_mismatch}

  @doc """
  Update a card's body. Author-only, brainstorm-only.
  """
  def update_card(%RetroCard{} = card, body, user_id, %RetroSession{status: "brainstorm"})
      when is_binary(user_id) do
    cond do
      card.author_user_id != user_id ->
        {:error, :not_author}

      true ->
        card
        |> RetroCard.body_changeset(%{body: body})
        |> Repo.update()
    end
  end

  def update_card(_, _, _, _), do: {:error, :brainstorm_only}

  @doc "Delete a card. Author-only, brainstorm-only."
  def delete_card(%RetroCard{} = card, user_id, %RetroSession{status: "brainstorm"})
      when is_binary(user_id) do
    if card.author_user_id == user_id do
      Repo.delete(card)
    else
      {:error, :not_author}
    end
  end

  def delete_card(_, _, _), do: {:error, :brainstorm_only}

  @doc """
  Bulk-set vote counts on cards. Called by `Chambers.Server`
  when phase exits `:voting`. `counts` is a `%{card_id =>
  count}` map; cards not in the map keep their existing count
  (which should be 0 for a fresh session).
  """
  def materialize_vote_counts(%RetroSession{id: session_id}, counts)
      when is_map(counts) do
    Repo.transaction(fn ->
      Enum.each(counts, fn {card_id, count} ->
        from(c in RetroCard,
          where: c.id == ^card_id and c.retro_session_id == ^session_id
        )
        |> Repo.update_all(
          set: [vote_count: count, updated_at: DateTime.utc_now() |> DateTime.truncate(:second)]
        )
      end)
    end)
  end

  # --- Merge (spec §20) --------------------------------------------

  @doc """
  Fold `source` into `target` during `:reveal`: the source keeps its
  row but is hidden from the board and rendered under the target.
  Any cards already merged into the source follow it to the target,
  so groups stay one level deep.
  """
  def merge_card(%RetroCard{} = source, %RetroCard{} = target, %RetroSession{} = session) do
    cond do
      session.status != "reveal" ->
        {:error, :reveal_only}

      source.id == target.id ->
        {:error, :same_card}

      source.retro_session_id != session.id or target.retro_session_id != session.id ->
        {:error, :wrong_session}

      not is_nil(target.merged_into_card_id) ->
        {:error, :target_is_merged}

      true ->
        Repo.transaction(fn ->
          now = DateTime.utc_now() |> DateTime.truncate(:second)

          from(c in RetroCard, where: c.merged_into_card_id == ^source.id)
          |> Repo.update_all(set: [merged_into_card_id: target.id, updated_at: now])

          source
          |> Ecto.Changeset.change(merged_into_card_id: target.id)
          |> Repo.update!()
        end)
    end
  end

  @doc "Undo a merge: the card stands on its own again (`:reveal` only)."
  def unmerge_card(%RetroCard{merged_into_card_id: nil} = card, _session), do: {:ok, card}

  def unmerge_card(%RetroCard{} = card, %RetroSession{status: "reveal"}) do
    card |> Ecto.Changeset.change(merged_into_card_id: nil) |> Repo.update()
  end

  def unmerge_card(_, _), do: {:error, :reveal_only}

  @doc "Load a single card by id."
  def get_card(card_id) when is_binary(card_id) do
    Repo.get(RetroCard, card_id)
  end

  @doc "Load a single column by id."
  def get_column(column_id) when is_binary(column_id) do
    Repo.get(RetroColumn, column_id)
  end

  # ---------------------------------------------------------------
  # Action items
  # ---------------------------------------------------------------

  @doc """
  Add an action item during `:discuss`. `source_card_id` is
  optional (nil = freeform action).
  """
  def add_action_item(%RetroSession{status: "discuss", id: session_id}, attrs) do
    %RetroActionItem{}
    |> RetroActionItem.creation_changeset(Map.put(attrs, :retro_session_id, session_id))
    |> Repo.insert()
  end

  def add_action_item(%RetroSession{}, _attrs), do: {:error, :discuss_only}

  @doc "Update an action item. Allowed during `:discuss` only in v1."
  def update_action_item(%RetroActionItem{} = action, attrs, %RetroSession{status: "discuss"}) do
    action
    |> RetroActionItem.update_changeset(attrs)
    |> Repo.update()
  end

  def update_action_item(_, _, _), do: {:error, :discuss_only}

  @doc "Delete an action item. Discuss-phase only."
  def delete_action_item(%RetroActionItem{} = action, %RetroSession{status: "discuss"}) do
    Repo.delete(action)
  end

  def delete_action_item(_, _), do: {:error, :discuss_only}

  # --- Carry-over (spec §13) ---------------------------------------

  @doc """
  Open action items from a team's *archived* retros: not completed,
  not already carried forward. Session title preloaded for the
  "from Sprint 12" label. Empty for sessions without a team.
  """
  def open_previous_action_items(%RetroSession{team_id: nil}), do: []

  def open_previous_action_items(%RetroSession{team_id: team_id, id: session_id}) do
    Repo.all(from a in open_team_actions_query(team_id), where: a.retro_session_id != ^session_id)
  end

  @doc "Every open item across a team's archived retros (drives `/t/:slug`)."
  def open_team_action_items(team_id) when is_binary(team_id) do
    Repo.all(open_team_actions_query(team_id))
  end

  defp open_team_actions_query(team_id) do
    from a in RetroActionItem,
      join: s in assoc(a, :session),
      where:
        s.team_id == ^team_id and s.status == "archived" and
          a.completed == false and is_nil(a.carried_over_at),
      order_by: [desc: s.archived_at, asc: a.inserted_at],
      preload: [session: s]
  end

  @doc """
  Copy `previous` into `session` as a freeform item and stamp the
  original as carried over. Allowed in any live phase — carry-over
  happens on :setup, before :discuss unlocks regular item creation.
  """
  def carry_over_action_item(
        %RetroSession{status: status} = session,
        %RetroActionItem{} = previous,
        user_id
      )
      when status != "archived" do
    Repo.transaction(fn ->
      attrs = %{
        retro_session_id: session.id,
        body: previous.body,
        assignee_alias: previous.assignee_alias,
        due_date: previous.due_date,
        created_by_user_id: user_id
      }

      with {:ok, copy} <-
             Repo.insert(RetroActionItem.creation_changeset(%RetroActionItem{}, attrs)),
           {:ok, _} <-
             previous
             |> Ecto.Changeset.change(carried_over_at: DateTime.utc_now(:second))
             |> Repo.update() do
        copy
      else
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  def carry_over_action_item(_, _, _), do: {:error, :archived}

  @doc "Mark a previous retro's open item done out-of-band (from the current retro or /t/:slug)."
  def complete_previous_action_item(%RetroActionItem{} = previous) do
    previous
    |> Ecto.Changeset.change(completed: true)
    |> Repo.update()
  end

  @doc "Load a single action item by id."
  def get_action_item(id) when is_binary(id) do
    Repo.get(RetroActionItem, id)
  end

  # ---------------------------------------------------------------
  # Reactions
  # ---------------------------------------------------------------

  @reactable_statuses ~w(reveal voting discuss)

  # Brainstorm is normally non-interactive (cards are hidden
  # from non-authors). When the host turned on brainstorm_visible
  # at :setup, cards are live-visible to everyone — so reacting
  # and commenting make sense there too.
  defp interactive?(%RetroSession{status: status}) when status in @reactable_statuses,
    do: true

  defp interactive?(%RetroSession{status: "brainstorm", brainstorm_visible: true}),
    do: true

  defp interactive?(_), do: false

  @doc """
  Toggle a user's reaction on a card. Cards become reactable
  from `:reveal` onward, plus during `:brainstorm` when the
  session is in always-visible mode. Returns `{:added, reaction}`
  or `{:removed, count}` so the caller knows which way the
  toggle went; `{:error, ...}` otherwise.
  """
  def toggle_reaction(%RetroCard{} = card, user_id, emoji, %RetroSession{} = session)
      when is_binary(user_id) and is_binary(emoji) do
    cond do
      not interactive?(session) ->
        {:error, :phase_locked}

      byte_size(emoji) == 0 or byte_size(emoji) > 32 ->
        {:error, :invalid_emoji}

      true ->
        query =
          from r in RetroCardReaction,
            where: r.retro_card_id == ^card.id and r.user_id == ^user_id and r.emoji == ^emoji

        case Repo.one(query) do
          nil ->
            case %RetroCardReaction{}
                 |> RetroCardReaction.creation_changeset(%{
                   retro_card_id: card.id,
                   user_id: user_id,
                   emoji: emoji
                 })
                 |> Repo.insert() do
              {:ok, reaction} -> {:added, reaction}
              other -> other
            end

          existing ->
            {1, _} = Repo.delete_all(from(r in RetroCardReaction, where: r.id == ^existing.id))
            {:removed, existing}
        end
    end
  end

  def toggle_reaction(_, _, _, _), do: {:error, :phase_locked}

  # ---------------------------------------------------------------
  # Comments
  # ---------------------------------------------------------------

  @doc """
  Add a comment to a card. Anyone in the chamber, during any
  interactive phase (reveal/voting/discuss + brainstorm when
  brainstorm_visible is on). `attrs` must include body +
  author_alias; optionally author_user_id + author_display_name.
  """
  def add_comment(%RetroCard{} = card, attrs, %RetroSession{} = session) do
    if interactive?(session) do
      %RetroCardComment{}
      |> RetroCardComment.creation_changeset(Map.put(attrs, :retro_card_id, card.id))
      |> Repo.insert()
    else
      {:error, :phase_locked}
    end
  end

  @doc "Author-only edit during interactive phases."
  def update_comment(%RetroCardComment{} = comment, body, user_id, %RetroSession{} = session)
      when is_binary(user_id) do
    cond do
      not interactive?(session) ->
        {:error, :phase_locked}

      comment.author_user_id != user_id ->
        {:error, :not_author}

      true ->
        comment
        |> RetroCardComment.body_changeset(%{body: body})
        |> Repo.update()
    end
  end

  @doc "Author-only delete during interactive phases."
  def delete_comment(%RetroCardComment{} = comment, user_id, %RetroSession{} = session)
      when is_binary(user_id) do
    cond do
      not interactive?(session) -> {:error, :phase_locked}
      comment.author_user_id != user_id -> {:error, :not_author}
      true -> Repo.delete(comment)
    end
  end

  @doc "Load a single comment by id."
  def get_comment(id) when is_binary(id), do: Repo.get(RetroCardComment, id)
end
