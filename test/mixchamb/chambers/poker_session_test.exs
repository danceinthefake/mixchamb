defmodule Mixchamb.Chambers.PokerSessionTest do
  use ExUnit.Case, async: true

  alias Mixchamb.Chambers.PokerSession

  describe "new/1" do
    test "defaults to fibonacci, voting, no votes, round 1" do
      s = PokerSession.new()
      assert s.status == :voting
      assert s.deck == :fibonacci
      assert s.votes == %{}
      assert s.round == 1
      assert is_nil(s.story)
    end

    test "honors a non-default deck" do
      assert %{deck: :tshirt} = PokerSession.new(:tshirt)
    end
  end

  describe "cards_for/1" do
    test "returns the right values per deck, including ? and ☕ where applicable" do
      assert PokerSession.cards_for(:fibonacci) == ~w(1 2 3 5 8 13 21 ? ☕)
      assert PokerSession.cards_for(:tshirt) == ~w(XS S M L XL ?)
      assert "☕" in PokerSession.cards_for(:pow2)
      assert "100" in PokerSession.cards_for(:modified_fibonacci)
    end
  end

  describe "cast_vote/3" do
    test "records the vote during :voting" do
      s = PokerSession.new()
      assert {:ok, updated} = PokerSession.cast_vote(s, "alice", "5")
      assert updated.votes == %{"alice" => "5"}
    end

    test "is idempotent — same card by same user is a no-op" do
      s = %{PokerSession.new() | votes: %{"alice" => "5"}}
      assert {:noop, ^s} = PokerSession.cast_vote(s, "alice", "5")
    end

    test "lets a user change their vote during :voting" do
      s = %{PokerSession.new() | votes: %{"alice" => "5"}}
      assert {:ok, updated} = PokerSession.cast_vote(s, "alice", "8")
      assert updated.votes == %{"alice" => "8"}
    end

    test "rejects a card that isn't in the active deck" do
      s = PokerSession.new(:tshirt)
      assert {:error, :invalid_card} = PokerSession.cast_vote(s, "alice", "13")
    end

    test "is a no-op during :revealed" do
      s = %{PokerSession.new() | status: :revealed}
      assert {:noop, ^s} = PokerSession.cast_vote(s, "alice", "5")
    end
  end

  describe "withdraw_vote/2" do
    test "drops a vote during :voting" do
      s = %{PokerSession.new() | votes: %{"alice" => "5", "bob" => "8"}}
      assert {:ok, updated} = PokerSession.withdraw_vote(s, "alice")
      assert updated.votes == %{"bob" => "8"}
    end

    test "is a no-op when the user hasn't voted" do
      s = PokerSession.new()
      assert {:noop, ^s} = PokerSession.withdraw_vote(s, "alice")
    end

    test "is a no-op during :revealed" do
      s = %{PokerSession.new() | status: :revealed, votes: %{"alice" => "5"}}
      assert {:noop, ^s} = PokerSession.withdraw_vote(s, "alice")
    end
  end

  describe "reveal/1" do
    test "flips :voting to :revealed, preserving votes" do
      s = %{PokerSession.new() | votes: %{"alice" => "5"}}
      assert {:ok, updated} = PokerSession.reveal(s)
      assert updated.status == :revealed
      assert updated.votes == %{"alice" => "5"}
    end

    test "reveal with zero votes is allowed (no gate)" do
      s = PokerSession.new()
      assert {:ok, %{status: :revealed, votes: %{}}} = PokerSession.reveal(s)
    end

    test "re-revealing is a no-op" do
      s = %{PokerSession.new() | status: :revealed}
      assert {:noop, ^s} = PokerSession.reveal(s)
    end
  end

  describe "next_round/2" do
    test "clears votes, increments round, returns to :voting" do
      s = %{
        PokerSession.new()
        | status: :revealed,
          votes: %{"alice" => "5", "bob" => "8"},
          round: 3,
          story: "Add dark mode"
      }

      assert {:ok, updated} = PokerSession.next_round(s)
      assert updated.status == :voting
      assert updated.votes == %{}
      assert updated.round == 4
      # Story carries over unless explicitly replaced.
      assert updated.story == "Add dark mode"
    end

    test "swaps the story when :story is passed" do
      s = %{PokerSession.new() | story: "Old"}
      assert {:ok, %{story: "New"}} = PokerSession.next_round(s, story: "New")
    end
  end

  describe "set_story/2" do
    test "updates the story line" do
      s = PokerSession.new()
      assert {:ok, %{story: "Estimate the migration"}} =
               PokerSession.set_story(s, "Estimate the migration")
    end

    test "nil clears the story" do
      s = %{PokerSession.new() | story: "Old"}
      assert {:ok, %{story: nil}} = PokerSession.set_story(s, nil)
    end

    test "no-op when the story is unchanged" do
      s = %{PokerSession.new() | story: "Same"}
      assert {:noop, ^s} = PokerSession.set_story(s, "Same")
    end
  end

  describe "set_deck/2" do
    test "switches deck when no votes are cast" do
      s = PokerSession.new()
      assert {:ok, %{deck: :tshirt}} = PokerSession.set_deck(s, :tshirt)
    end

    test "rejects the switch when votes are in progress" do
      s = %{PokerSession.new() | votes: %{"alice" => "5"}}
      assert {:error, :votes_in_progress} = PokerSession.set_deck(s, :tshirt)
    end

    test "no-op when switching to the same deck" do
      s = PokerSession.new(:pow2)
      assert {:noop, ^s} = PokerSession.set_deck(s, :pow2)
    end

    test "rejects an unknown deck" do
      s = PokerSession.new()
      assert {:error, :invalid_deck} = PokerSession.set_deck(s, :no_such_deck)
    end
  end
end
