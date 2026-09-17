defmodule Mixchamb.Chambers.ServerEdgesTest do
  @moduledoc """
  The GenServer's rejection branches, no-op fall-throughs, timers
  and lifecycle messages — the paths a happy-path flow never hits.
  """
  use Mixchamb.DataCase, async: false

  alias Mixchamb.{Accounts, Chambers, Retro}
  alias Mixchamb.Chambers.Server
  alias Mixchamb.MiniGame.State

  setup do
    {:ok, host} = Accounts.create_anonymous_user()
    {:ok, other} = Accounts.create_anonymous_user()
    %{host: host, other: other}
  end

  defp start(user, activity) do
    {:ok, chamber} = Chambers.create_chamber(user.id, activity)
    {:ok, pid} = Server.ensure_started(chamber.slug, chamber.id)
    Phoenix.PubSub.subscribe(Mixchamb.PubSub, Chambers.topic(chamber.slug))

    on_exit(fn ->
      if Process.alive?(pid),
        do: DynamicSupervisor.terminate_child(Mixchamb.Chambers.Supervisor, pid)
    end)

    {chamber, pid}
  end

  defp settle(slug), do: Server.hosts(slug)

  test "retro + poker casts against a music chamber are silent no-ops", %{host: host} do
    {chamber, _} = start(host, "music")
    slug = chamber.slug
    id = host.id

    Server.retro_start_session(slug, id)
    Server.retro_set_title(slug, id, "t")
    Server.retro_set_team(slug, id, "t")
    Server.retro_set_timer(slug, id, 5)
    Server.retro_set_brainstorm_visible(slug, id, true)
    Server.retro_set_voting_enabled(slug, id, true)
    Server.retro_rename_column(slug, id, "c", "n")
    Server.retro_advance_phase(slug, id)
    Server.retro_add_card(slug, id, "c", "b", "a", "d")
    Server.retro_update_card(slug, id, "c", "b")
    Server.retro_delete_card(slug, id, "c")
    Server.retro_vote(slug, id, "c")
    Server.retro_withdraw_vote(slug, id, "c")
    Server.retro_set_discussing(slug, id, "c")
    Server.retro_add_action_item(slug, %{body: "x"})
    Server.retro_update_action_item(slug, "a", %{})
    Server.retro_delete_action_item(slug, "a")
    Server.retro_carry_over_action(slug, id, "a")
    Server.retro_complete_previous_action(slug, "a")
    Server.retro_toggle_reaction(slug, id, "c", "x")
    Server.retro_add_comment(slug, id, "c", "b", "a", "d")
    Server.retro_update_comment(slug, id, "c", "b")
    Server.retro_delete_comment(slug, id, "c")

    Server.poker_vote(slug, id, "3")
    Server.poker_withdraw_vote(slug, id)
    Server.poker_reveal(slug)
    Server.poker_revote(slug)
    Server.poker_next_round(slug, nil)
    Server.poker_set_story(slug, "s")
    Server.poker_set_deck(slug, :fibonacci)
    Server.poker_set_queue(slug, ["a"])

    settle(slug)
    refute_receive {:retro, _, _}, 50
    refute_receive {:poker, _, _}, 50
    assert Server.retro_state(slug) == nil
    assert Server.poker_state(slug) == nil
  end

  test "retro actions rejected by the context leave state untouched", %{host: host, other: other} do
    {chamber, _} = start(host, "retro")
    slug = chamber.slug
    Server.retro_start_session(slug, host.id)
    assert_receive {:retro, :session_started, sid}, 500
    [col | _] = Retro.load_session(sid).columns

    # Wrong phase for cards / votes / actions / reactions / comments.
    Server.retro_add_card(slug, other.id, col.id, "early", "o", "o")
    Server.retro_vote(slug, other.id, "nope")
    Server.retro_withdraw_vote(slug, other.id, "nope")
    Server.retro_add_action_item(slug, %{body: "early"})
    Server.retro_update_action_item(slug, Ecto.UUID.generate(), %{body: "x"})
    Server.retro_delete_action_item(slug, Ecto.UUID.generate())
    Server.retro_toggle_reaction(slug, other.id, Ecto.UUID.generate(), "🔥")
    Server.retro_add_comment(slug, other.id, Ecto.UUID.generate(), "b", "o", "o")
    Server.retro_update_comment(slug, other.id, Ecto.UUID.generate(), "b")
    Server.retro_delete_comment(slug, other.id, Ecto.UUID.generate())
    Server.retro_update_card(slug, other.id, Ecto.UUID.generate(), "b")
    Server.retro_delete_card(slug, other.id, Ecto.UUID.generate())
    Server.retro_carry_over_action(slug, host.id, Ecto.UUID.generate())
    Server.retro_complete_previous_action(slug, Ecto.UUID.generate())
    Server.retro_rename_column(slug, host.id, Ecto.UUID.generate(), "ghost")
    Server.retro_set_timer(slug, host.id, -1)
    settle(slug)
    refute_receive {:retro, _, _}, 50
    assert Retro.load_session(sid).cards == []

    # Brainstorm → a card exists; edits by a non-author are refused,
    # renames are locked, brainstorm-visibility is locked.
    Server.retro_advance_phase(slug, host.id)
    assert_receive {:retro, :phase_changed, :brainstorm}, 500
    Server.retro_add_card(slug, host.id, col.id, "mine", "h", "h")
    assert_receive {:retro, :card_added, _}, 500
    [card] = Retro.load_session(sid).cards
    Server.retro_update_card(slug, other.id, card.id, "stolen")
    Server.retro_delete_card(slug, other.id, card.id)
    Server.retro_rename_column(slug, host.id, col.id, "late")
    Server.retro_set_brainstorm_visible(slug, host.id, true)
    Server.retro_set_discussing(slug, host.id, card.id)
    settle(slug)
    refute_receive {:retro, _, _}, 50
    assert Retro.get_card(card.id).body == "mine"

    # Comment edit / delete by a stranger, reaction toggled twice (removed).
    Server.retro_advance_phase(slug, host.id)
    assert_receive {:retro, :phase_changed, :reveal}, 500
    Server.retro_add_comment(slug, host.id, card.id, "c", "h", "h")
    assert_receive {:retro, :comment_added, _}, 500
    [%{comments: [comment]}] = Retro.load_session(sid).cards
    Server.retro_update_comment(slug, other.id, comment.id, "hijack")
    Server.retro_delete_comment(slug, other.id, comment.id)
    settle(slug)
    assert Retro.get_comment(comment.id).body == "c"
    Server.retro_toggle_reaction(slug, other.id, card.id, "🔥")
    assert_receive {:retro, :reaction_toggled, _, _, "🔥", :added}, 500
    Server.retro_toggle_reaction(slug, other.id, card.id, "🔥")
    assert_receive {:retro, :reaction_toggled, _, _, "🔥", :removed}, 500

    # Voting: a repeat vote on the same card and a withdraw with no
    # vote are both no-ops.
    Server.retro_set_voting_enabled(slug, host.id, true)
    assert_receive {:retro, :voting_enabled_changed, true}, 500
    Server.retro_advance_phase(slug, host.id)
    assert_receive {:retro, :phase_changed, :voting}, 500
    Server.retro_vote(slug, other.id, card.id)
    assert_receive {:retro, :vote_cast, _, _, _}, 500
    Server.retro_vote(slug, other.id, card.id)
    Server.retro_withdraw_vote(slug, host.id, card.id)
    settle(slug)
    refute_receive {:retro, _, _, _, _}, 50
  end

  test "pictionary timers: choice expiry, turn expiry, letter reveal, reveal advance, drawer grace",
       %{host: host, other: other} do
    {chamber, pid} = start(host, "minigame")
    slug = chamber.slug
    Server.minigame_set_config(slug, host.id, %{"round_count" => 1})
    assert_receive {:minigame, :changed}, 500
    Server.minigame_start(slug, host.id, [host.id, other.id])
    assert_receive {:minigame, :changed}, 500
    mg = Server.minigame_state(slug)

    # Stale tokens are ignored.
    for msg <- [
          {:minigame_expire, -1},
          {:minigame_choice_expire, -1},
          {:minigame_reveal_letter, -1},
          {:minigame_reveal_advance, -1},
          {:minigame_drawer_grace, -1},
          {:minigame_step_expire, -1}
        ],
        do: send(pid, msg)

    refute_receive {:minigame, :changed}, 50

    # Choice expiry auto-picks the first word as the drawer.
    first = hd(mg.word_choices)
    send(pid, {:minigame_choice_expire, mg.turn_token})
    assert_receive {:minigame, :changed}, 500
    mg = Server.minigame_state(slug)
    assert mg.word == first

    # Letter reveal drips one letter.
    send(pid, {:minigame_reveal_letter, mg.turn_token})
    settle(slug)
    assert Server.minigame_state(slug).revealed >= mg.revealed

    # Drawer drops → grace hold → grace expiry prunes them and ends the turn.
    Server.minigame_presence_sync(slug, [other.id])
    assert_receive {:minigame, :changed}, 500
    assert Server.minigame_state(slug).drawer_away
    send(pid, {:minigame_drawer_grace, mg.turn_token})
    assert_receive {:minigame, :changed}, 500
    refute mg.drawer_id in Server.minigame_state(slug).players
  end

  test "turn expiry + reveal advance drive a game to completion", %{host: host, other: other} do
    {chamber, pid} = start(host, "minigame")
    slug = chamber.slug
    Server.minigame_set_config(slug, host.id, %{"round_count" => 1})
    assert_receive {:minigame, :changed}, 500
    Server.minigame_start(slug, host.id, [host.id, other.id])
    assert_receive {:minigame, :changed}, 500
    mg = Server.minigame_state(slug)
    Server.minigame_choose_word(slug, mg.drawer_id, hd(mg.word_choices))
    assert_receive {:minigame, :changed}, 500

    send(pid, {:minigame_expire, Server.minigame_state(slug).turn_token})
    assert_receive {:minigame, :changed}, 500
    %State{phase: :turn_reveal, turn_token: token} = Server.minigame_state(slug)

    send(pid, {:minigame_reveal_advance, token})
    assert_receive {:minigame, :changed}, 500
    assert Server.minigame_state(slug).phase in [:turn, :gameover]
  end

  test "gartic step expiry fills stragglers and advances", %{host: host, other: other} do
    {:ok, third} = Accounts.create_anonymous_user()
    {chamber, pid} = start(host, "minigame")
    slug = chamber.slug
    Server.minigame_select_game(slug, host.id, "gartic_phone")
    assert_receive {:minigame, :changed}, 500
    Server.minigame_start(slug, host.id, [host.id, other.id, third.id])
    assert_receive {:minigame, :changed}, 500
    %State{turn_token: token} = Server.minigame_state(slug)

    send(pid, {:minigame_step_expire, token})
    assert_receive {:minigame, :changed}, 500
    assert Server.minigame_state(slug).game_state.step == 1

    # Host force-skip also advances a step.
    Server.minigame_skip(slug, host.id)
    assert_receive {:minigame, :changed}, 500
    assert Server.minigame_state(slug).game_state.step == 2
  end

  test "recording: notes queue while REC is on and flush on the timer / off", %{host: host} do
    {chamber, pid} = start(host, "music")
    slug = chamber.slug
    {:ok, chamber} = Chambers.set_recording(chamber, true)
    Chambers.broadcast_note(slug, %{"instrument" => "drums", "note" => "kick"})
    settle(slug)
    send(pid, :flush_recording)
    settle(slug)
    assert Chambers.recorded_event_count(chamber.id) == 1

    Chambers.broadcast_note(slug, %{"instrument" => "drums", "note" => "snare"})
    {:ok, _} = Chambers.set_recording(chamber, false)
    settle(slug)
    assert Chambers.recorded_event_count(chamber.id) == 2

    # Off: further notes aren't persisted.
    Chambers.broadcast_note(slug, %{"instrument" => "drums", "note" => "hat"})
    send(pid, :flush_recording)
    settle(slug)
    assert Chambers.recorded_event_count(chamber.id) == 2
  end

  test "check_grace: unactivated chamber deletes itself; activated one stays", %{host: host} do
    {chamber, pid} = start(host, "music")
    ref = Process.monitor(pid)
    send(pid, :check_grace)
    assert_receive {:chamber_closed, _}, 500
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 500
    assert Chambers.find_by_slug(chamber.slug) == nil

    {chamber2, pid2} = start(host, "music")
    {:ok, _} = Chambers.mark_active(chamber2)
    send(pid2, :check_grace)
    settle(chamber2.slug)
    assert Process.alive?(pid2)

    # Row deleted out-of-band → the grace check just stops.
    {chamber3, pid3} = start(host, "music")
    ref3 = Process.monitor(pid3)
    Chambers.delete(chamber3)
    send(pid3, :check_grace)
    assert_receive {:DOWN, ^ref3, :process, ^pid3, :normal}, 500
  end

  test "bump_activity stops the server when the row is gone", %{host: host} do
    {chamber, pid} = start(host, "music")
    ref = Process.monitor(pid)
    Chambers.broadcast_note(chamber.slug, %{"instrument" => "drums", "note" => "kick"})
    settle(chamber.slug)
    Chambers.delete(chamber)
    send(pid, :bump_activity)
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 500
  end

  test "system chamber (no creator) survives the grace check" do
    {:ok, chaos} = Chambers.ensure_chaos_chamber()
    {:ok, pid} = Server.ensure_started(chaos.slug, chaos.id)
    on_exit(fn -> DynamicSupervisor.terminate_child(Mixchamb.Chambers.Supervisor, pid) end)
    send(pid, :check_grace)
    settle(chaos.slug)
    assert Process.alive?(pid)
    assert Server.hosts(chaos.slug) == []
  end
end
