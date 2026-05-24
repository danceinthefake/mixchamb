defmodule Mixchamb.Retro.EphemeralState do
  @moduledoc """
  Per-chamber ephemeral state for the retro activity. Owned by
  `Mixchamb.Chambers.Server`'s GenServer state. Mirrors the role
  `Mixchamb.Chambers.PokerSession` plays for poker.

  Holds *only* what dies with the chamber:

    * the current session id (so handlers know which DB session
      they're operating on without re-querying)
    * the live phase (mirrored from DB for fast access without a
      query per broadcast)
    * the per-user vote map during `:voting` — `%{user_id =>
      MapSet[card_id]}`. Cleared on phase exit; counts materialise
      into `retro_cards.vote_count`.
    * the "currently discussing" card focus during `:discuss`

  Persistent state (sessions, columns, cards, action items) lives
  in Postgres via the `Mixchamb.Retro` context — this struct is
  only the volatile slice.

  Mutation functions return one of:

    * `{:ok, new_state}` — state changed; caller should broadcast
    * `{:noop, state}`   — no-op; caller skips broadcast
    * `{:error, reason}` — validation failure
  """

  @vote_cap 3
  def vote_cap, do: @vote_cap

  # Pre-declare every phase atom so `String.to_existing_atom/1`
  # in `Chambers.Server` (which converts the DB string back to an
  # atom for EphemeralState.phase) always succeeds. Without this,
  # atoms only referenced via type specs (e.g. :brainstorm,
  # :reveal, :archived) wouldn't exist in the atom table until
  # something else materialised them, and the first advance from
  # :setup would crash the chamber GenServer.
  @phases ~w(setup brainstorm reveal voting discuss archived)a
  def phases, do: @phases

  defstruct session_id: nil,
            phase: :setup,
            votes: %{},
            discussing_card_id: nil

  @type t :: %__MODULE__{
          session_id: binary() | nil,
          phase: :setup | :brainstorm | :reveal | :voting | :discuss | :archived,
          votes: %{optional(binary()) => MapSet.t(binary())},
          discussing_card_id: binary() | nil
        }

  @doc "Fresh state pointing at the given session, defaulting to :setup."
  def new(session_id, phase \\ :setup)
      when is_binary(session_id) and is_atom(phase) do
    %__MODULE__{session_id: session_id, phase: phase}
  end

  @doc """
  Cast a vote for a card during `:voting`. Enforces the 3-vote
  per-user cap. Re-voting for the same card is a no-op.
  """
  def cast_vote(%__MODULE__{phase: :voting} = s, user_id, card_id)
      when is_binary(user_id) and is_binary(card_id) do
    current = Map.get(s.votes, user_id, MapSet.new())

    cond do
      MapSet.member?(current, card_id) ->
        {:noop, s}

      MapSet.size(current) >= @vote_cap ->
        {:error, :vote_limit_reached}

      true ->
        updated = MapSet.put(current, card_id)
        {:ok, %{s | votes: Map.put(s.votes, user_id, updated)}}
    end
  end

  def cast_vote(%__MODULE__{} = s, _user_id, _card_id), do: {:noop, s}

  @doc """
  Withdraw a vote for a card. No-op if the user hasn't voted for
  that card. Also fires on Presence leave to clear all votes for
  the leaver (use `clear_user_votes/2` for that bulk variant).
  """
  def withdraw_vote(%__MODULE__{phase: :voting} = s, user_id, card_id)
      when is_binary(user_id) and is_binary(card_id) do
    current = Map.get(s.votes, user_id, MapSet.new())

    if MapSet.member?(current, card_id) do
      updated = MapSet.delete(current, card_id)
      new_votes = if MapSet.size(updated) == 0, do: Map.delete(s.votes, user_id), else: Map.put(s.votes, user_id, updated)
      {:ok, %{s | votes: new_votes}}
    else
      {:noop, s}
    end
  end

  def withdraw_vote(%__MODULE__{} = s, _user_id, _card_id), do: {:noop, s}

  @doc "Drop all of a user's votes (e.g. on chamber leave)."
  def clear_user_votes(%__MODULE__{} = s, user_id) when is_binary(user_id) do
    if Map.has_key?(s.votes, user_id) do
      {:ok, %{s | votes: Map.delete(s.votes, user_id)}}
    else
      {:noop, s}
    end
  end

  @doc """
  Materialise per-card vote counts from the user-keyed vote map,
  for caller to push into `retro_cards.vote_count`. Returns a
  `%{card_id => count}` map.
  """
  def tally(%__MODULE__{votes: votes}) do
    votes
    |> Map.values()
    |> Enum.reduce(%{}, fn ms, acc ->
      Enum.reduce(ms, acc, fn card_id, acc2 ->
        Map.update(acc2, card_id, 1, &(&1 + 1))
      end)
    end)
  end

  @doc "Set the discussing-card focus (or clear with nil)."
  def set_discussing(%__MODULE__{phase: :discuss} = s, card_id_or_nil)
      when is_binary(card_id_or_nil) or is_nil(card_id_or_nil) do
    if s.discussing_card_id == card_id_or_nil do
      {:noop, s}
    else
      {:ok, %{s | discussing_card_id: card_id_or_nil}}
    end
  end

  def set_discussing(%__MODULE__{} = s, _), do: {:noop, s}

  @doc "Advance to a new phase. Clears phase-scoped state on exit."
  def set_phase(%__MODULE__{} = s, phase) when is_atom(phase) do
    cleared =
      case {s.phase, phase} do
        # Exiting :voting clears the vote map (counts are
        # expected to have been materialised by the caller before
        # this fires).
        {:voting, _} -> %{s | votes: %{}}
        # Exiting :discuss clears the discussing focus.
        {:discuss, _} -> %{s | discussing_card_id: nil}
        _ -> s
      end

    {:ok, %{cleared | phase: phase}}
  end
end
