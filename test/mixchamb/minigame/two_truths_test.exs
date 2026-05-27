defmodule Mixchamb.MiniGame.TwoTruthsTest do
  use ExUnit.Case, async: true

  alias Mixchamb.MiniGame.{TwoTruths, State}

  defp tt(players) do
    {:ok, s} = State.select_game(State.new(), "two_truths")
    {:ok, s} = State.start(s, players)
    s
  end

  defp write(s, uid, items, lie) do
    {:ok, s2, _} =
      TwoTruths.handle_action(s, {:submit, %{"items" => items, "lie" => lie}}, %{user_id: uid})

    s2
  end

  defp guess(s, uid, pick) do
    {:ok, s2, _} = TwoTruths.handle_action(s, {:submit, %{"lie_guess" => pick}}, %{user_id: uid})
    s2
  end

  # Everyone writes (lie at index 0 for simplicity).
  defp all_write(s) do
    Enum.reduce(s.players, s, fn uid, acc ->
      write(acc, uid, ["lie-#{uid}", "true-#{uid}-1", "true-#{uid}-2"], 0)
    end)
  end

  describe "lifecycle / config" do
    test "starts in writing with a deadline; needs 3 players" do
      {:ok, s} = State.select_game(State.new(), "two_truths")
      assert s.config == %{write_seconds: 90, guess_seconds: 30}
      assert {:error, :need_more_players} = State.start(s, ~w(a b))

      s = tt(~w(a b c))
      assert s.phase == :writing
      assert is_integer(s.turn_deadline)
      assert s.game_state.n == 3
    end

    test "config clamps both timers" do
      {:ok, s} = State.select_game(State.new(), "two_truths")
      {:ok, s} = State.set_config(s, %{"write_seconds" => "120", "guess_seconds" => 45})
      assert s.config == %{write_seconds: 120, guess_seconds: 45}
      {:ok, s} = State.set_config(s, %{"guess_seconds" => 999})
      assert s.config[:guess_seconds] == 45
    end
  end

  describe "writing" do
    test "submitting marks done; all-in advances to guessing the first author" do
      s = tt(~w(a b c)) |> write("a", ["x", "y", "z"], 1)
      assert TwoTruths.view(s, "a").submitted
      assert s.phase == :writing

      s = s |> write("b", ["p", "q", "r"], 0) |> write("c", ["m", "n", "o"], 2)
      assert s.phase == :guessing
      assert Enum.at(s.game_state.order, 0) == "a"
    end

    test "rejects bad submissions" do
      s = tt(~w(a b c))

      assert {:error, :invalid} =
               TwoTruths.handle_action(s, {:submit, %{"items" => ["x", "y"], "lie" => 0}}, %{
                 user_id: "a"
               })

      assert {:error, :invalid} =
               TwoTruths.handle_action(s, {:submit, %{"items" => ["x", "y", "z"], "lie" => 5}}, %{
                 user_id: "a"
               })

      s = write(s, "a", ["x", "y", "z"], 0)

      assert {:error, :already_submitted} =
               TwoTruths.handle_action(s, {:submit, %{"items" => ["a", "b", "c"], "lie" => 0}}, %{
                 user_id: "a"
               })
    end
  end

  describe "guessing" do
    test "the author can't guess; statements are shuffled with the lie hidden" do
      s = tt(~w(a b c)) |> all_write()
      author = Enum.at(s.game_state.order, 0)

      assert {:error, :is_author} =
               TwoTruths.handle_action(s, {:submit, %{"lie_guess" => 0}}, %{user_id: author})

      v = TwoTruths.view(s, "b")
      assert v.phase == "guessing"
      assert length(v.statements) == 3
      refute Map.has_key?(v, :lie_index), "lie position withheld during guessing"
    end

    test "all guessers in → reveal, with the lie + picks exposed" do
      s = tt(~w(a b c)) |> all_write()
      author = Enum.at(s.game_state.order, 0)
      lie = s.game_state.lie_display
      [g1, g2] = Enum.reject(s.players, &(&1 == author))

      s = guess(s, g1, lie)
      assert s.phase == :guessing, "waits for the other guesser"
      s = guess(s, g2, rem(lie + 1, 3))
      assert s.phase == :reveal

      v = TwoTruths.view(s, g1)
      assert v.lie_index == lie
      assert v.picks[g1] == lie
    end

    test "scoring: spotter +10, author +5 per fooled" do
      s = tt(~w(a b c)) |> all_write()
      author = Enum.at(s.game_state.order, 0)
      lie = s.game_state.lie_display
      [g1, g2] = Enum.reject(s.players, &(&1 == author))

      s = s |> guess(g1, lie) |> guess(g2, rem(lie + 1, 3))

      assert s.scores[g1] == 10, "g1 spotted the lie"
      assert s.scores[author] == 5, "author fooled g2"
      assert s.scores[g2] == 0
    end
  end

  describe "rotation + game over" do
    test "advance walks guessing → reveal per author, then ends" do
      s = tt(~w(a b c)) |> all_write()
      assert s.phase == :guessing and s.game_state.current == 0

      s = TwoTruths.advance(s)
      assert s.phase == :reveal and s.game_state.current == 0

      s = TwoTruths.advance(s)
      assert s.phase == :guessing and s.game_state.current == 1

      # reveal 1 → guessing 2
      s = s |> TwoTruths.advance() |> TwoTruths.advance()
      assert s.phase == :guessing and s.game_state.current == 2

      # reveal 2 → game over
      s = s |> TwoTruths.advance() |> TwoTruths.advance()
      assert s.phase == :gameover
    end

    test "no-shows are dropped from the author rotation but the round still runs" do
      # only a + b write; c never does. Force-advance writing.
      s = tt(~w(a b c)) |> write("a", ["x", "y", "z"], 0) |> write("b", ["p", "q", "r"], 1)
      s = TwoTruths.advance(s)
      assert s.phase == :guessing
      assert s.game_state.order == ~w(a b), "c (no statements) isn't an author"
    end
  end
end
