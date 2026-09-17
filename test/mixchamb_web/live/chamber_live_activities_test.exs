defmodule MixchambWeb.ChamberLiveActivitiesTest do
  @moduledoc """
  Event + PubSub routing through `ChamberLive` into the per-activity
  modules (retro / minigame / poker / music) over connected views.
  The GenServer is the source of truth, so most assertions read
  `Server.*_state/1` after the cast lands.
  """
  use MixchambWeb.ConnCase, async: false

  alias Mixchamb.{Accounts, Chambers, Retro}
  alias Mixchamb.Chambers.Server

  setup %{conn: conn} do
    {:ok, user} = Accounts.create_anonymous_user()
    {:ok, other} = Accounts.create_anonymous_user()
    conn = Plug.Test.init_test_session(conn, %{"user_id" => user.id})
    other_conn = Plug.Test.init_test_session(build_conn(), %{"user_id" => other.id})
    %{conn: conn, other_conn: other_conn, user: user, other: other}
  end

  defp start_chamber(user, activity) do
    {:ok, chamber} = Chambers.create_chamber(user.id, activity)
    {:ok, _} = Server.ensure_started(chamber.slug, chamber.id)

    on_exit(fn ->
      case Registry.lookup(Mixchamb.Chambers.Registry, chamber.slug) do
        [{pid, _}] -> DynamicSupervisor.terminate_child(Mixchamb.Chambers.Supervisor, pid)
        _ -> :ok
      end
    end)

    chamber
  end

  # Casts are async; a GenServer.call afterwards serialises behind them.
  defp settle(slug), do: Server.hosts(slug)

  defp retro_session(chamber), do: Retro.current_session(chamber.id)

  # ------------------------------------------------------------------
  # Retro
  # ------------------------------------------------------------------

  describe "retro events" do
    setup %{user: user, conn: conn, other_conn: other_conn} do
      chamber = start_chamber(user, "retro")
      {:ok, host, _} = live(conn, ~p"/chamber/#{chamber.slug}")
      {:ok, guest, _} = live(other_conn, ~p"/chamber/#{chamber.slug}")
      %{chamber: chamber, host: host, guest: guest}
    end

    test "full lifecycle through the LV", %{chamber: chamber, host: host, guest: guest} = ctx do
      slug = chamber.slug

      # Guest can't start; host can.
      render_hook(guest, "retro_start_session", %{})
      settle(slug)
      assert retro_session(chamber) == nil
      render_hook(host, "retro_start_session", %{})
      settle(slug)
      session = retro_session(chamber)
      assert session.status == "setup"

      render_hook(host, "retro_set_title", %{"title" => "Sprint 9"})
      render_hook(host, "retro_set_team", %{"team" => "Core"})
      render_hook(host, "retro_set_voting_enabled", %{"enabled" => true})
      render_hook(host, "retro_set_brainstorm_visible", %{"visible" => true})
      [col | _] = Retro.load_session(session.id).columns
      render_hook(host, "retro_rename_column", %{"column_id" => col.id, "name" => "Wins"})
      render_hook(host, "retro_set_timer", %{"seconds" => 60, "auto_advance" => true})
      settle(slug)

      loaded = Retro.load_session(session.id)
      assert loaded.title == "Sprint 9"
      assert loaded.team.slug == "core"
      assert loaded.voting_enabled
      assert loaded.brainstorm_visible
      assert hd(loaded.columns).name == "Wins"
      assert is_integer(Server.retro_state(slug).timer_deadline)
      assert Server.retro_state(slug).auto_advance
      assert :sys.get_state(guest.pid).socket.assigns.retro_timer_auto
      render_hook(host, "retro_set_timer", %{"seconds" => nil})
      settle(slug)
      assert Server.retro_state(slug).timer_deadline == nil

      # Guest-issued host actions are dropped at the LV fast-path.
      render_hook(guest, "retro_set_title", %{"title" => "hijack"})
      render_hook(guest, "retro_set_team", %{"team" => "x"})
      render_hook(guest, "retro_set_voting_enabled", %{"enabled" => false})
      render_hook(guest, "retro_set_brainstorm_visible", %{"visible" => false})
      render_hook(guest, "retro_rename_column", %{"column_id" => col.id, "name" => "no"})
      render_hook(guest, "retro_set_timer", %{"seconds" => 5})
      render_hook(guest, "retro_advance_phase", %{})
      settle(slug)
      assert Retro.load_session(session.id).title == "Sprint 9"
      assert Retro.load_session(session.id).status == "setup"

      # → brainstorm: both add cards, guest edits + deletes theirs.
      render_hook(host, "retro_advance_phase", %{})
      settle(slug)
      render_hook(host, "retro_add_card", %{"column_id" => col.id, "body" => "host card"})
      render_hook(guest, "retro_add_card", %{"column_id" => col.id, "body" => "guest card"})
      settle(slug)
      cards = Retro.load_session(session.id).cards
      assert length(cards) == 2
      guest_card = Enum.find(cards, &(&1.body == "guest card"))
      host_card = Enum.find(cards, &(&1.body == "host card"))

      render_hook(guest, "retro_update_card", %{"card_id" => guest_card.id, "body" => "edited"})
      settle(slug)
      assert Retro.get_card(guest_card.id).body == "edited"
      render_hook(guest, "retro_delete_card", %{"card_id" => guest_card.id})
      settle(slug)
      assert Retro.get_card(guest_card.id) == nil

      # → reveal: reactions + comments; merge a second card into the
      # host's and check the folded wire shape.
      render_hook(host, "retro_add_card", %{"column_id" => col.id, "body" => "dup"})
      settle(slug)
      dup = Enum.find(Retro.load_session(session.id).cards, &(&1.body == "dup"))
      render_hook(host, "retro_advance_phase", %{})
      settle(slug)

      render_hook(guest, "retro_merge_card", %{"source_id" => dup.id, "target_id" => host_card.id})

      settle(slug)
      assert Retro.get_card(dup.id).merged_into_card_id == nil
      render_hook(host, "retro_merge_card", %{"source_id" => dup.id, "target_id" => host_card.id})
      settle(slug)
      assert Retro.get_card(dup.id).merged_into_card_id == host_card.id

      folded =
        Enum.find(
          MixchambWeb.ChamberLive.Retro.view(Retro.load_session(session.id)).cards,
          &(&1.id == host_card.id)
        )

      assert [%{body: "dup"}] = folded.merged
      render_hook(guest, "retro_unmerge_card", %{"card_id" => dup.id})
      render_hook(host, "retro_unmerge_card", %{"card_id" => dup.id})
      settle(slug)
      assert Retro.get_card(dup.id).merged_into_card_id == nil
      render_hook(host, "retro_merge_card", %{"source_id" => dup.id, "target_id" => host_card.id})
      settle(slug)
      render_hook(guest, "retro_toggle_reaction", %{"card_id" => host_card.id, "emoji" => "🔥"})
      render_hook(guest, "retro_add_comment", %{"card_id" => host_card.id, "body" => "yes"})
      settle(slug)
      [comment] = Retro.load_session(session.id).cards |> hd() |> Map.get(:comments)
      render_hook(guest, "retro_update_comment", %{"comment_id" => comment.id, "body" => "yes!"})
      settle(slug)
      assert Retro.get_comment(comment.id).body == "yes!"
      render_hook(guest, "retro_delete_comment", %{"comment_id" => comment.id})
      settle(slug)
      assert Retro.get_comment(comment.id) == nil
      assert [%{emoji: "🔥"}] = Retro.load_session(session.id).cards |> hd() |> Map.get(:reactions)

      # → voting: vote, withdraw, vote again; tallies reach the LV.
      render_hook(host, "retro_advance_phase", %{})
      settle(slug)
      render_hook(guest, "retro_vote", %{"card_id" => host_card.id})
      render_hook(guest, "retro_withdraw_vote", %{"card_id" => host_card.id})
      render_hook(guest, "retro_vote", %{"card_id" => host_card.id})
      settle(slug)
      assert Retro.EphemeralState.tally(Server.retro_state(slug)) == %{host_card.id => 1}
      assert render(guest) =~ "retro_my_votes"

      # → discuss: focus, action items (add / update / delete), carry-over no-op.
      render_hook(host, "retro_advance_phase", %{})
      settle(slug)
      render_hook(guest, "retro_set_discussing", %{"card_id" => host_card.id})
      settle(slug)
      assert Server.retro_state(slug).discussing_card_id == nil
      render_hook(host, "retro_set_discussing", %{"card_id" => host_card.id})
      settle(slug)
      assert Server.retro_state(slug).discussing_card_id == host_card.id
      # Visited set reaches every client (drives the Next → stepper).
      assert :sys.get_state(guest.pid).socket.assigns.retro_discussed == [host_card.id]
      render_hook(host, "retro_set_discussing", %{"card_id" => nil})
      settle(slug)
      assert Server.retro_state(slug).discussing_card_id == nil
      assert MapSet.member?(Server.retro_state(slug).discussed, host_card.id)

      render_hook(guest, "retro_add_action_item", %{
        "body" => "do it",
        "source_card_id" => host_card.id,
        "assignee_alias" => "me",
        "due_date" => "2026-10-01"
      })

      settle(slug)
      [action] = Retro.load_session(session.id).action_items
      assert action.assignee_alias == "me"

      render_hook(guest, "retro_update_action_item", %{
        "action_id" => action.id,
        "body" => "done it",
        "completed" => true
      })

      settle(slug)
      assert %{completed: true, body: "done it"} = Retro.get_action_item(action.id)
      render_hook(guest, "retro_carry_over_action", %{"action_id" => action.id})
      render_hook(guest, "retro_complete_previous_action", %{"action_id" => action.id})
      settle(slug)
      render_hook(guest, "retro_delete_action_item", %{"action_id" => action.id})
      settle(slug)
      assert Retro.get_action_item(action.id) == nil

      # → archived: past_retros grows on both views.
      render_hook(host, "retro_advance_phase", %{})
      settle(slug)
      assert Retro.load_session(session.id).status == "archived"
      assert render(host) =~ "Past retros (1)"
      assert render(guest) =~ "Past retros (1)"
      _ = ctx
    end
  end

  describe "retro broadcasts" do
    setup %{user: user, conn: conn} do
      chamber = start_chamber(user, "retro")
      {:ok, view, _} = live(conn, ~p"/chamber/#{chamber.slug}")
      %{chamber: chamber, view: view}
    end

    test "every wire arity is routed without crashing", %{chamber: chamber, view: view} do
      topic = Chambers.topic(chamber.slug)

      for msg <- [
            {:retro, :title_changed, "t"},
            {:retro, :card_edited, "a", "b"},
            {:retro, :card_merged, "a", "b"},
            {:retro, :card_unmerged, "a"},
            {:retro, :vote_cast, "u", "c", %{"c" => 1}},
            {:retro, :vote_withdrawn, "u", "c", %{}},
            {:retro, :reaction_toggled, "c", "u", "🔥", :added},
            {:retro, :discussing, "card-1", ["card-1"]},
            {:retro, :timer, %{deadline: 123, auto_advance: false}},
            {:retro, :team_changed, nil},
            {:retro, :phase_changed, :brainstorm},
            {:retro, :phase_changed, :archived}
          ] do
        Phoenix.PubSub.broadcast(Mixchamb.PubSub, topic, msg)
      end

      assert render(view)
      assert Process.alive?(view.pid)
    end
  end

  # ------------------------------------------------------------------
  # Mini-game
  # ------------------------------------------------------------------

  describe "minigame events" do
    setup %{user: user, conn: conn, other_conn: other_conn} do
      chamber = start_chamber(user, "minigame")
      {:ok, host, _} = live(conn, ~p"/chamber/#{chamber.slug}")
      {:ok, guest, _} = live(other_conn, ~p"/chamber/#{chamber.slug}")
      %{chamber: chamber, host: host, guest: guest}
    end

    test "pictionary round through the LV", %{chamber: chamber, host: host, guest: guest} do
      slug = chamber.slug

      render_hook(host, "minigame_select_game", %{"game" => "pictionary"})
      render_hook(host, "minigame_set_config", %{"config" => %{"round_count" => 1}})
      # Players come from presence: both connected views are tracked.
      render_hook(host, "minigame_start", %{})
      settle(slug)
      mg = Server.minigame_state(slug)
      assert mg.phase == :turn
      assert length(mg.players) == 2

      {drawer, guesser} = if mg.drawer_id == user_id(host), do: {host, guest}, else: {guest, host}
      word = hd(mg.word_choices)

      render_hook(drawer, "minigame_choose_word", %{"word" => word})
      render_hook(drawer, "minigame_stroke", %{"pts" => [1]})
      render_hook(drawer, "minigame_stroke_end", %{"pts" => [1]})
      render_hook(drawer, "minigame_undo", %{})
      render_hook(drawer, "minigame_stroke_end", %{"pts" => [2]})
      render_hook(drawer, "minigame_clear", %{})
      settle(slug)
      assert Server.minigame_state(slug).strokes == []

      # Relays + feed are pushed to the client as events.
      render_hook(guesser, "minigame_guess", %{"text" => "wrong-#{word}"})
      assert_push_event(guesser, "minigame_feed", %{})
      assert_push_event(guesser, "minigame_relay", %{kind: "clear"})

      render_hook(guesser, "minigame_guess", %{"text" => word})
      settle(slug)
      assert MapSet.member?(Server.minigame_state(slug).guessed, user_id(guesser))

      render_hook(host, "minigame_skip", %{})
      settle(slug)
      assert Server.minigame_state(slug).phase == :turn_reveal
      render_hook(host, "minigame_next", %{})
      settle(slug)
      render_hook(host, "minigame_play_again", %{})
      settle(slug)
      assert Server.minigame_state(slug).phase == :lobby
      render_hook(host, "minigame_end", %{})
      settle(slug)
      assert Server.minigame_state(slug).phase == :lobby
    end

    test "gartic submit + album_next route through", %{chamber: chamber, host: host} do
      slug = chamber.slug
      render_hook(host, "minigame_select_game", %{"game" => "gartic_phone"})
      settle(slug)
      # Only 2 present → below gartic's minimum; start is rejected.
      render_hook(host, "minigame_start", %{})
      settle(slug)
      assert Server.minigame_state(slug).phase == :lobby
      render_hook(host, "minigame_submit", %{"text" => "x", "_target" => ["text"]})
      render_hook(host, "minigame_album_next", %{})
      settle(slug)
      assert Process.alive?(host.pid)
    end
  end

  # ------------------------------------------------------------------
  # Poker / shell / music odds and ends
  # ------------------------------------------------------------------

  describe "poker + shell" do
    setup %{user: user, conn: conn, other_conn: other_conn} do
      chamber = start_chamber(user, "poker")
      {:ok, host, _} = live(conn, ~p"/chamber/#{chamber.slug}")
      {:ok, guest, _} = live(other_conn, ~p"/chamber/#{chamber.slug}")
      %{chamber: chamber, host: host, guest: guest}
    end

    test "poker_revote clears votes; 5-tuple broadcasts reload", %{chamber: chamber} = ctx do
      %{host: host, guest: guest} = ctx
      slug = chamber.slug
      render_hook(guest, "poker_vote", %{"card" => "3"})
      render_hook(host, "poker_reveal", %{})
      settle(slug)
      assert Server.poker_state(slug).status == :revealed
      render_hook(guest, "poker_revote", %{})
      settle(slug)
      assert Server.poker_state(slug).status == :revealed
      render_hook(host, "poker_revote", %{})
      settle(slug)
      assert Server.poker_state(slug).status == :voting
      assert Server.poker_state(slug).votes == %{}

      # Guest-issued host-only actions are dropped.
      render_hook(guest, "poker_set_story", %{"story" => "hijack"})
      render_hook(guest, "poker_set_deck", %{"deck" => "tshirt"})
      render_hook(guest, "poker_set_queue", %{"queue" => ["a"]})
      render_hook(guest, "poker_next_round", %{})
      settle(slug)
      assert Server.poker_state(slug).story == nil

      Phoenix.PubSub.broadcast(
        Mixchamb.PubSub,
        Chambers.topic(slug),
        {:poker, :vote_cast, "u", "c", %{}}
      )

      assert render(host)
    end

    test "hosts_changed / chamber_updated / activity_changed / chamber_closed",
         %{chamber: chamber, host: host, guest: guest, other: other} do
      topic = Chambers.topic(chamber.slug)

      render_hook(host, "promote_host", %{"user_id" => other.id})
      settle(chamber.slug)
      assert render(guest) =~ "Host"
      render_hook(guest, "demote_host", %{"user_id" => other.id})
      settle(chamber.slug)

      render_hook(host, "save_title", %{"title" => "Renamed"})
      assert render(guest) =~ "Renamed"
      render_hook(guest, "save_title", %{"title" => "Nope"})
      assert Chambers.find_by_slug(chamber.slug).title == "Renamed"
      render_hook(host, "save_title", %{"title" => String.duplicate("x", 500)})
      assert render(host) =~ "Couldn"

      Phoenix.PubSub.broadcast(Mixchamb.PubSub, topic, {:activity_changed, "retro"})
      assert render(guest) =~ "Host switched the chamber to Retro"

      Phoenix.PubSub.broadcast(Mixchamb.PubSub, topic, {:chamber_closed, chamber.slug})
      assert_redirect(guest, "/")
    end
  end

  describe "music extras" do
    setup %{user: user, conn: conn} do
      chamber = start_chamber(user, "music")
      {:ok, view, _} = live(conn, ~p"/chamber/#{chamber.slug}")
      %{chamber: chamber, view: view}
    end

    test "recent-hits feed handles chord / pad / release / unknown-instrument payloads + expiry",
         %{chamber: chamber, view: view} do
      topic = Chambers.topic(chamber.slug)

      for payload <- [
            %{"user_id" => "x", "instrument" => "guitar", "chord" => "Am", "alias" => "al"},
            %{"user_id" => "x", "instrument" => "pad", "pad" => "P1", "display_name" => "dn"},
            %{"user_id" => "x", "instrument" => "not-an-instrument", "note" => "C4"},
            %{"user_id" => "x", "instrument" => "kazoo", "note" => "C4"},
            %{"user_id" => "x", "note" => "C4"},
            %{"user_id" => "x", "instrument" => "drums", "phase" => "release", "note" => "kick"}
          ] do
        Phoenix.PubSub.broadcast(
          Mixchamb.PubSub,
          topic,
          {:chamber_note, %{kind: :note, payload: payload}}
        )
      end

      html = render(view)
      assert html =~ "Am" and html =~ "P1"
      send(view.pid, {:expire_hit, -1})
      assert render(view)

      # Empty replay (no events yet) still pushes a burst.
      render_hook(view, "request_replay", %{})
      assert_push_event(view, "replay_burst", %{events: []})
      render_hook(view, "play_recording", %{})
      assert_push_event(view, "replay_burst", %{events: []})
    end

    test "request_replay pushes a burst; audio_downloaded clears the flag; same kind is a no-op",
         %{chamber: chamber, view: view} do
      render_hook(view, "note", %{"instrument" => "drums", "note" => "kick"})
      render_hook(view, "request_replay", %{})
      assert_push_event(view, "replay_burst", %{events: [_ | _]})

      render_hook(view, "audio_downloaded", %{})
      render_hook(view, "set_kind", %{"kind" => chamber.kind})
      assert Chambers.find_by_slug(chamber.slug).kind == chamber.kind

      # Reset while recording is refused.
      render_hook(view, "toggle_recording", %{})
      assert render_hook(view, "reset_recording", %{}) =~ "Stop recording before resetting."
      render_hook(view, "toggle_recording", %{})

      # Unknown instrument + cooldown path.
      render_hook(view, "switch_instrument", %{"to" => "keyboard"})
      render_hook(view, "switch_instrument", %{"to" => "guitar"})
      assert render(view) =~ "aria-pressed=\"true\""
    end
  end

  defp user_id(view), do: :sys.get_state(view.pid).socket.assigns.current_user.id
end
