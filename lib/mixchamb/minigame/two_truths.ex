defmodule Mixchamb.MiniGame.TwoTruths do
  @moduledoc """
  Third registry game: Two Truths and a Lie. No authored content — every
  statement is typed by a player at runtime, so there's nothing to seed
  or store.

  Flow (framework `phase`): `:writing → :guessing → :reveal → … →
  :gameover`.
  - **writing** — everyone simultaneously submits three statements (two
    true, one lie) and marks which is the lie. Private until guessing.
  - **guessing** — one author at a time: their three statements show in
    a shuffled order (the lie position withheld); everyone else picks
    which they think is the lie.
  - **reveal** — the lie is shown with everyone's picks. Spotters score;
    the author scores for each person they fooled. Then the next author.

  Game-specific data lives in `state.game_state`; scoring rides the
  shared `state.scores`; `turn_deadline` / `turn_token` drive the
  per-phase clock + timer guard (the generic step timer in
  `Chambers.Server` covers `:writing` / `:guessing`).
  """

  @behaviour Mixchamb.MiniGame.Game

  alias Mixchamb.MiniGame.State

  @write_seconds_options [60, 90, 120]
  @guess_seconds_options [20, 30, 45]
  @text_max 120
  @spot_points 10
  @fool_points 5

  ## --- config ----------------------------------------------------

  @impl true
  def default_config, do: %{write_seconds: 90, guess_seconds: 30}

  # Author + at least two guessers makes it fun.
  @impl true
  def min_players, do: 3

  @impl true
  def sanitize_config(current, partial) when is_map(current) and is_map(partial) do
    current
    |> clamp(partial, "write_seconds", :write_seconds, @write_seconds_options)
    |> clamp(partial, "guess_seconds", :guess_seconds, @guess_seconds_options)
  end

  defp clamp(config, partial, str_key, atom_key, allowed) do
    n = coerce(partial[str_key])
    if n in allowed, do: Map.put(config, atom_key, n), else: config
  end

  defp coerce(v) when is_binary(v) do
    case Integer.parse(v) do
      {n, ""} -> n
      _ -> v
    end
  end

  defp coerce(v), do: v

  ## --- lifecycle -------------------------------------------------

  @impl true
  def init(%State{players: players} = state) do
    gs = %{
      n: length(players),
      order: [],
      current: 0,
      statements: %{},
      submitted: MapSet.new(),
      display: [],
      lie_display: nil,
      guesses: %{}
    }

    %{
      state
      | phase: :writing,
        turn_deadline: now() + state.config[:write_seconds] * 1000,
        turn_token: state.turn_token + 1,
        game_state: gs
    }
  end

  @impl true
  def advance(%State{phase: :writing} = state), do: start_guessing_phase(state)
  def advance(%State{phase: :guessing} = state), do: to_reveal(state)

  def advance(%State{phase: :reveal, game_state: gs} = state),
    do: start_guessing(state, gs.current + 1)

  def advance(%State{} = state), do: state

  ## --- actions ---------------------------------------------------

  @impl true
  # Writing phase: submit three statements + which index is the lie.
  def handle_action(%State{phase: :writing, game_state: gs} = state, {:submit, payload}, %{
        user_id: user_id
      }) do
    items = payload["items"] || payload[:items]
    lie = payload["lie"] || payload[:lie]

    cond do
      user_id not in state.players ->
        {:error, :not_a_player}

      MapSet.member?(gs.submitted, user_id) ->
        {:error, :already_submitted}

      not valid_statements?(items, lie) ->
        {:error, :invalid}

      true ->
        entry = %{items: Enum.map(items, &clean/1), lie: lie}

        gs = %{
          gs
          | statements: Map.put(gs.statements, user_id, entry),
            submitted: MapSet.put(gs.submitted, user_id)
        }

        state = %{state | game_state: gs}

        if MapSet.size(gs.submitted) >= gs.n,
          do: {:ok, start_guessing_phase(state), [:changed]},
          else: {:ok, state, [:changed]}
    end
  end

  # Guessing phase: pick which displayed statement is the lie.
  def handle_action(%State{phase: :guessing, game_state: gs} = state, {:submit, payload}, %{
        user_id: user_id
      }) do
    pick = payload["lie_guess"] || payload[:lie_guess]
    author = Enum.at(gs.order, gs.current)

    cond do
      user_id == author -> {:error, :is_author}
      user_id not in state.players -> {:error, :not_a_player}
      Map.has_key?(gs.guesses, user_id) -> {:error, :already_guessed}
      not (is_integer(pick) and pick in 0..2) -> {:error, :invalid}
      true -> register_guess(state, gs, user_id, pick)
    end
  end

  def handle_action(%State{}, {:submit, _}, _ctx), do: {:error, :not_playing}

  # Host force-advance (skip the wait / next author).
  def handle_action(%State{phase: phase} = state, :skip, _ctx)
      when phase in [:writing, :guessing, :reveal],
      do: {:ok, advance(state), [:changed]}

  def handle_action(%State{}, _action, _ctx), do: {:error, :not_allowed}

  ## --- per-user view ---------------------------------------------

  @impl true
  def view(%State{phase: :writing, game_state: gs} = state, user_id) do
    %{
      game: "two_truths",
      phase: "writing",
      is_player: user_id in state.players,
      submitted: MapSet.member?(gs.submitted, user_id),
      submitted_count: MapSet.size(gs.submitted),
      player_count: gs.n,
      deadline: state.turn_deadline,
      turn_token: state.turn_token
    }
  end

  def view(%State{phase: :guessing, game_state: gs} = state, user_id) do
    author = Enum.at(gs.order, gs.current)

    base_round(state, gs, author)
    |> Map.merge(%{
      phase: "guessing",
      # Shuffled statement texts — the lie position is withheld.
      statements: gs.display,
      is_author: user_id == author,
      my_guess: Map.get(gs.guesses, user_id),
      guessed: Map.keys(gs.guesses)
    })
  end

  def view(%State{phase: :reveal, game_state: gs} = state, _user_id) do
    author = Enum.at(gs.order, gs.current)

    base_round(state, gs, author)
    |> Map.merge(%{
      phase: "reveal",
      statements: gs.display,
      # Now safe to expose which statement was the lie + everyone's picks.
      lie_index: gs.lie_display,
      picks: gs.guesses
    })
  end

  def view(%State{phase: :gameover} = state, _user_id) do
    %{
      game: "two_truths",
      phase: "gameover",
      players: state.players,
      scores: state.scores
    }
  end

  def view(%State{} = state, _user_id),
    do: %{
      game: "two_truths",
      phase: Atom.to_string(state.phase),
      config: %{
        write_seconds: state.config[:write_seconds],
        guess_seconds: state.config[:guess_seconds]
      },
      min_players: min_players()
    }

  ## --- internals -------------------------------------------------

  defp base_round(state, gs, author) do
    %{
      game: "two_truths",
      author: author,
      author_index: gs.current,
      total_authors: length(gs.order),
      guessed_count: map_size(gs.guesses),
      guesser_count: length(state.players) - 1,
      players: state.players,
      scores: state.scores,
      deadline: state.turn_deadline,
      turn_token: state.turn_token
    }
  end

  defp register_guess(state, gs, user_id, pick) do
    gs = %{gs | guesses: Map.put(gs.guesses, user_id, pick)}
    state = %{state | game_state: gs}

    # Everyone who can guess has → reveal.
    if map_size(gs.guesses) >= guesser_count(state),
      do: {:ok, to_reveal(state), [:changed]},
      else: {:ok, state, [:changed]}
  end

  defp guesser_count(state), do: max(0, length(state.players) - 1)

  # Move from writing into guessing the first author. Only players who
  # actually submitted statements become authors (a no-show can still
  # guess others, just has no book of their own).
  defp start_guessing_phase(%State{game_state: gs} = state) do
    order = Enum.filter(state.players, &Map.has_key?(gs.statements, &1))
    start_guessing(%{state | game_state: %{gs | order: order}}, 0)
  end

  defp start_guessing(%State{game_state: gs} = state, index) do
    if index >= length(gs.order) do
      %{state | phase: :gameover, turn_deadline: nil}
    else
      author = Enum.at(gs.order, index)
      %{items: items, lie: lie} = gs.statements[author]
      perm = Enum.shuffle(0..2)
      display = Enum.map(perm, &Enum.at(items, &1))
      lie_display = Enum.find_index(perm, &(&1 == lie))

      %{
        state
        | phase: :guessing,
          turn_deadline: now() + state.config[:guess_seconds] * 1000,
          turn_token: state.turn_token + 1,
          game_state: %{
            gs
            | current: index,
              display: display,
              lie_display: lie_display,
              guesses: %{}
          }
      }
    end
  end

  # Score the round: spotters who found the lie score; the author scores
  # for each guesser they fooled.
  defp to_reveal(%State{game_state: gs} = state) do
    author = Enum.at(gs.order, gs.current)

    scores =
      Enum.reduce(gs.guesses, state.scores, fn {guesser, pick}, acc ->
        if pick == gs.lie_display do
          bump(acc, guesser, @spot_points)
        else
          bump(acc, author, @fool_points)
        end
      end)

    %{state | phase: :reveal, turn_deadline: nil, scores: scores}
  end

  defp bump(scores, user_id, points), do: Map.update(scores, user_id, points, &(&1 + points))

  defp valid_statements?(items, lie) do
    is_list(items) and length(items) == 3 and
      Enum.all?(items, &(is_binary(&1) and clean(&1) != "")) and
      is_integer(lie) and lie in 0..2
  end

  defp clean(t) when is_binary(t), do: t |> String.trim() |> String.slice(0, @text_max)
  defp clean(_), do: ""

  defp now, do: System.system_time(:millisecond)
end
