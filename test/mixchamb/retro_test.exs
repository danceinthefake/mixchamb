defmodule Mixchamb.RetroTest do
  use Mixchamb.DataCase, async: false

  alias Mixchamb.{Accounts, Chambers, Retro}
  alias Mixchamb.Retro.RetroSession

  setup do
    {:ok, user} = Accounts.create_anonymous_user()
    {:ok, chamber} = Chambers.create_chamber(user.id, "retro")
    %{user: user, chamber: chamber}
  end

  describe "start_session/2" do
    test "creates session + 4 default columns", %{chamber: chamber} do
      assert {:ok, session} = Retro.start_session(chamber.id)
      assert session.status == "setup"
      assert session.voting_enabled == false
      assert length(session.columns) == 4
      assert Enum.map(session.columns, & &1.name) == ["Good", "Bad", "Start", "Thanks"]
      assert Enum.map(session.columns, & &1.position) == [0, 1, 2, 3]
    end

    test "refuses second session while one is active", %{chamber: chamber} do
      assert {:ok, _} = Retro.start_session(chamber.id)
      assert {:error, :session_already_active} = Retro.start_session(chamber.id)
    end

    test "accepts optional title", %{chamber: chamber} do
      assert {:ok, session} = Retro.start_session(chamber.id, %{title: "Sprint 23"})
      assert session.title == "Sprint 23"
    end
  end

  describe "current_session/1 + load_session/1" do
    test "current_session returns the non-archived session", %{chamber: chamber} do
      {:ok, started} = Retro.start_session(chamber.id)
      current = Retro.current_session(chamber.id)
      assert current.id == started.id
    end

    test "current_session is nil after archive", %{chamber: chamber, user: user} do
      {:ok, s} = Retro.start_session(chamber.id)
      s = advance_to(s, "archived", user)
      assert s.status == "archived"
      assert Retro.current_session(chamber.id) == nil
    end

    test "load_session preloads columns + cards + action items", %{chamber: chamber} do
      {:ok, session} = Retro.start_session(chamber.id)
      loaded = Retro.load_session(session.id)
      assert length(loaded.columns) == 4
      assert loaded.cards == []
      assert loaded.action_items == []
    end
  end

  describe "advance_phase/1" do
    test "voting disabled: setup → brainstorm → reveal → discuss → archived",
         %{chamber: chamber} do
      {:ok, s} = Retro.start_session(chamber.id)
      assert s.status == "setup"
      assert {:ok, s} = Retro.advance_phase(s)
      assert s.status == "brainstorm"
      assert {:ok, s} = Retro.advance_phase(s)
      assert s.status == "reveal"
      assert s.revealed_at != nil
      assert {:ok, s} = Retro.advance_phase(s)
      assert s.status == "discuss"
      assert {:ok, s} = Retro.advance_phase(s)
      assert s.status == "archived"
      assert s.archived_at != nil
    end

    test "voting enabled: reveal → voting → discuss",
         %{chamber: chamber} do
      {:ok, s} = Retro.start_session(chamber.id, %{voting_enabled: true})
      {:ok, s} = Retro.advance_phase(s)
      {:ok, s} = Retro.advance_phase(s)
      assert s.status == "reveal"
      {:ok, s} = Retro.advance_phase(s)
      assert s.status == "voting"
      {:ok, s} = Retro.advance_phase(s)
      assert s.status == "discuss"
    end

    test "rejects past archived", %{chamber: chamber, user: user} do
      {:ok, s} = Retro.start_session(chamber.id)
      s = advance_to(s, "archived", user)
      assert {:error, :already_archived} = Retro.advance_phase(s)
    end
  end

  describe "set_voting_enabled/2" do
    test "toggles freely before :discuss", %{chamber: chamber} do
      {:ok, s} = Retro.start_session(chamber.id)
      assert {:ok, s} = Retro.set_voting_enabled(s, true)
      assert s.voting_enabled == true
      {:ok, s} = Retro.advance_phase(s)
      assert {:ok, s} = Retro.set_voting_enabled(s, false)
      assert s.voting_enabled == false
    end

    test "rejects during :discuss", %{chamber: chamber, user: user} do
      {:ok, s} = Retro.start_session(chamber.id)
      s = advance_to(s, "discuss", user)
      assert {:error, :voting_locked} = Retro.set_voting_enabled(s, true)
    end

    test "rejects during :archived", %{chamber: chamber, user: user} do
      {:ok, s} = Retro.start_session(chamber.id)
      s = advance_to(s, "archived", user)
      assert {:error, :voting_locked} = Retro.set_voting_enabled(s, true)
    end
  end

  describe "rename_column/3" do
    test "renames during :setup", %{chamber: chamber} do
      {:ok, s} = Retro.start_session(chamber.id)
      [col | _] = s.columns
      assert {:ok, renamed} = Retro.rename_column(col, "Liked", s)
      assert renamed.name == "Liked"
    end

    test "rejects outside :setup", %{chamber: chamber} do
      {:ok, s} = Retro.start_session(chamber.id)
      [col | _] = s.columns
      {:ok, s} = Retro.advance_phase(s)
      assert s.status == "brainstorm"
      assert {:error, :rename_locked} = Retro.rename_column(col, "Liked", s)
    end
  end

  describe "add_card/3" do
    test "adds during :brainstorm with author info", %{chamber: chamber, user: user} do
      {:ok, s} = Retro.start_session(chamber.id)
      {:ok, s} = Retro.advance_phase(s)
      [col | _] = s.columns

      assert {:ok, card} =
               Retro.add_card(s, col, %{
                 body: "Pairing helped",
                 author_user_id: user.id,
                 author_alias: "Bold Otter 12"
               })

      assert card.body == "Pairing helped"
      assert card.author_alias == "Bold Otter 12"
      assert card.vote_count == 0
    end

    test "rejects outside :brainstorm", %{chamber: chamber, user: user} do
      {:ok, s} = Retro.start_session(chamber.id)
      [col | _] = s.columns

      assert {:error, :brainstorm_only} =
               Retro.add_card(s, col, %{body: "x", author_alias: "a"})

      s = advance_to(s, "reveal", user)

      assert {:error, :brainstorm_only} =
               Retro.add_card(s, col, %{body: "x", author_alias: "a"})
    end

    test "rejects whitespace-only body", %{chamber: chamber, user: user} do
      {:ok, s} = Retro.start_session(chamber.id)
      {:ok, s} = Retro.advance_phase(s)
      [col | _] = s.columns

      assert {:error, %Ecto.Changeset{}} =
               Retro.add_card(s, col, %{body: "   ", author_alias: "a", author_user_id: user.id})
    end

    test "rejects body > 280 chars", %{chamber: chamber, user: user} do
      {:ok, s} = Retro.start_session(chamber.id)
      {:ok, s} = Retro.advance_phase(s)
      [col | _] = s.columns

      assert {:error, %Ecto.Changeset{}} =
               Retro.add_card(s, col, %{
                 body: String.duplicate("a", 281),
                 author_alias: "a",
                 author_user_id: user.id
               })
    end
  end

  describe "update_card/4 + delete_card/3" do
    test "author can update + delete during :brainstorm",
         %{chamber: chamber, user: user} do
      {:ok, s} = Retro.start_session(chamber.id)
      {:ok, s} = Retro.advance_phase(s)
      [col | _] = s.columns

      {:ok, card} =
        Retro.add_card(s, col, %{
          body: "Pairing helped",
          author_user_id: user.id,
          author_alias: "a"
        })

      assert {:ok, updated} = Retro.update_card(card, "Pairing helped a lot", user.id, s)
      assert updated.body == "Pairing helped a lot"

      assert {:ok, _} = Retro.delete_card(card, user.id, s)
    end

    test "non-author cannot update or delete", %{chamber: chamber, user: user} do
      {:ok, other} = Accounts.create_anonymous_user()
      {:ok, s} = Retro.start_session(chamber.id)
      {:ok, s} = Retro.advance_phase(s)
      [col | _] = s.columns

      {:ok, card} =
        Retro.add_card(s, col, %{
          body: "Pairing",
          author_user_id: user.id,
          author_alias: "a"
        })

      assert {:error, :not_author} = Retro.update_card(card, "edit", other.id, s)
      assert {:error, :not_author} = Retro.delete_card(card, other.id, s)
    end

    test "rejects outside :brainstorm even by author", %{chamber: chamber, user: user} do
      {:ok, s} = Retro.start_session(chamber.id)
      {:ok, s} = Retro.advance_phase(s)
      [col | _] = s.columns

      {:ok, card} =
        Retro.add_card(s, col, %{
          body: "x",
          author_user_id: user.id,
          author_alias: "a"
        })

      {:ok, s} = Retro.advance_phase(s)
      assert s.status == "reveal"
      assert {:error, :brainstorm_only} = Retro.update_card(card, "edit", user.id, s)
      assert {:error, :brainstorm_only} = Retro.delete_card(card, user.id, s)
    end
  end

  describe "materialize_vote_counts/2" do
    test "writes counts onto the named cards only", %{chamber: chamber, user: user} do
      {:ok, s} = Retro.start_session(chamber.id)
      {:ok, s} = Retro.advance_phase(s)
      [col | _] = s.columns

      {:ok, c1} = Retro.add_card(s, col, %{body: "a", author_user_id: user.id, author_alias: "x"})
      {:ok, c2} = Retro.add_card(s, col, %{body: "b", author_user_id: user.id, author_alias: "x"})
      {:ok, c3} = Retro.add_card(s, col, %{body: "c", author_user_id: user.id, author_alias: "x"})

      assert {:ok, _} = Retro.materialize_vote_counts(s, %{c1.id => 3, c2.id => 1})

      assert Retro.get_card(c1.id).vote_count == 3
      assert Retro.get_card(c2.id).vote_count == 1
      assert Retro.get_card(c3.id).vote_count == 0
    end
  end

  describe "action items" do
    test "added during :discuss with optional source card",
         %{chamber: chamber, user: user} do
      {:ok, s} = Retro.start_session(chamber.id)
      {:ok, s} = Retro.advance_phase(s)
      [col | _] = s.columns
      {:ok, card} = Retro.add_card(s, col, %{body: "x", author_user_id: user.id, author_alias: "a"})
      s = advance_to(s, "discuss", user)

      assert {:ok, freeform} =
               Retro.add_action_item(s, %{body: "Talk to design", created_by_user_id: user.id})

      assert freeform.source_card_id == nil

      assert {:ok, tied} =
               Retro.add_action_item(s, %{
                 body: "Investigate deploy",
                 source_card_id: card.id,
                 assignee_alias: "Alex",
                 created_by_user_id: user.id
               })

      assert tied.source_card_id == card.id
      assert tied.assignee_alias == "Alex"
    end

    test "rejected outside :discuss", %{chamber: chamber} do
      {:ok, s} = Retro.start_session(chamber.id)
      assert {:error, :discuss_only} = Retro.add_action_item(s, %{body: "x"})
    end

    test "toggle completed during :discuss", %{chamber: chamber, user: user} do
      {:ok, s} = Retro.start_session(chamber.id)
      s = advance_to(s, "discuss", user)
      {:ok, action} = Retro.add_action_item(s, %{body: "x", created_by_user_id: user.id})
      assert {:ok, done} = Retro.update_action_item(action, %{completed: true}, s)
      assert done.completed == true
    end
  end

  describe "list_archived_sessions/1" do
    test "returns all archived sessions for the chamber", %{chamber: chamber, user: user} do
      {:ok, s1} = Retro.start_session(chamber.id, %{title: "First"})
      s1 = advance_to(s1, "archived", user)
      {:ok, s2} = Retro.start_session(chamber.id, %{title: "Second"})
      s2 = advance_to(s2, "archived", user)

      archived_ids = Retro.list_archived_sessions(chamber.id) |> Enum.map(& &1.id)
      assert length(archived_ids) == 2
      assert s1.id in archived_ids
      assert s2.id in archived_ids
    end
  end

  # Walk the phase machine to `target_status`. Voting is skipped
  # unless the test enabled it before calling this helper.
  defp advance_to(%RetroSession{status: status} = s, target, _user) when status == target, do: s

  defp advance_to(s, target, user) do
    {:ok, next} = Retro.advance_phase(s)
    advance_to(next, target, user)
  end
end
