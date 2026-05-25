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
    RetroActionItem
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
        Repo.transaction(fn ->
          case %RetroSession{}
               |> RetroSession.creation_changeset(Map.put(attrs, :chamber_id, chamber_id))
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

  defp load_associations(nil), do: nil

  defp load_associations(%RetroSession{} = session) do
    Repo.preload(session,
      columns: from(c in RetroColumn, order_by: [asc: c.position]),
      cards: from(c in RetroCard, order_by: [asc: c.inserted_at]),
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
        |> Repo.update_all(set: [vote_count: count, updated_at: DateTime.utc_now() |> DateTime.truncate(:second)])
      end)
    end)
  end

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
    |> RetroActionItem.creation_changeset(
      Map.put(attrs, :retro_session_id, session_id)
    )
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

  @doc "Load a single action item by id."
  def get_action_item(id) when is_binary(id) do
    Repo.get(RetroActionItem, id)
  end
end
