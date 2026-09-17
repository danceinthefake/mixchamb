defmodule Mixchamb.Chambers.ServerMiniGameTest do
  use Mixchamb.DataCase, async: false

  alias Mixchamb.{Accounts, Chambers}
  alias Mixchamb.Chambers.Server
  alias Mixchamb.MiniGame.State

  setup do
    {:ok, host} = Accounts.create_anonymous_user()
    {:ok, p2} = Accounts.create_anonymous_user()
    {:ok, p3} = Accounts.create_anonymous_user()
    {:ok, chamber} = Chambers.create_chamber(host.id, "minigame")
    {:ok, _pid} = Server.ensure_started(chamber.slug, chamber.id)
    Phoenix.PubSub.subscribe(Mixchamb.PubSub, Chambers.topic(chamber.slug))

    on_exit(fn ->
      case Registry.lookup(Mixchamb.Chambers.Registry, chamber.slug) do
        [{pid, _}] -> DynamicSupervisor.terminate_child(Mixchamb.Chambers.Supervisor, pid)
        _ -> :ok
      end
    end)

    %{host: host, p2: p2, p3: p3, slug: chamber.slug, players: [host.id, p2.id, p3.id]}
  end

  # Every state-changing cast broadcasts {:minigame, :changed}; wait
  # for it so the follow-up call sees the committed state.
  defp changed!, do: assert_receive({:minigame, :changed}, 500)
  defp no_change!, do: refute_receive({:minigame, :changed}, 100)

  describe "lobby" do
    test "host-only select / config / start / to_lobby",
         %{slug: slug, host: host, p2: p2} = ctx do
      Server.minigame_select_game(slug, p2.id, "two_truths")
      no_change!()
      Server.minigame_select_game(slug, host.id, "two_truths")
      changed!()
      assert Server.minigame_state(slug).game == "two_truths"

      Server.minigame_select_game(slug, host.id, "nope")
      no_change!()

      Server.minigame_select_game(slug, host.id, "pictionary")
      changed!()

      Server.minigame_set_config(slug, p2.id, %{"turn_seconds" => 60})
      no_change!()
      Server.minigame_set_config(slug, host.id, %{"turn_seconds" => 60})
      changed!()
      assert Server.minigame_state(slug).config.turn_seconds == 60

      Server.minigame_start(slug, p2.id, ctx.players)
      no_change!()
      # Below min players → rejected.
      Server.minigame_start(slug, host.id, [host.id])
      no_change!()
      Server.minigame_start(slug, host.id, ctx.players)
      changed!()
      assert %State{phase: :turn} = Server.minigame_state(slug)

      Server.minigame_to_lobby(slug, p2.id)
      no_change!()
      Server.minigame_to_lobby(slug, host.id)
      changed!()
      assert %State{phase: :lobby, players: []} = Server.minigame_state(slug)
    end
  end

  describe "pictionary" do
    setup %{slug: slug, host: host, players: players} do
      Server.minigame_set_config(slug, host.id, %{"round_count" => 1})
      changed!()
      Server.minigame_start(slug, host.id, players)
      changed!()
      mg = Server.minigame_state(slug)
      %{drawer: mg.drawer_id, word: hd(mg.word_choices)}
    end

    test "choose → draw relay → guess → skip → next", %{slug: slug} = ctx do
      %{drawer: drawer, word: word, host: host} = ctx
      guesser = Enum.find(ctx.players, &(&1 != drawer))

      # Non-drawer can't choose; drawer can.
      Server.minigame_choose_word(slug, guesser, word)
      no_change!()
      Server.minigame_choose_word(slug, drawer, word)
      changed!()
      assert Server.minigame_state(slug).word == word

      # Stroke relay is drawer-only, mid-turn.
      Server.minigame_stroke(slug, guesser, %{"pts" => [1, 2]})
      refute_receive {:minigame_relay, :stroke, _}, 100
      Server.minigame_stroke(slug, drawer, %{"pts" => [1, 2]})
      assert_receive {:minigame_relay, :stroke, %{"pts" => [1, 2], "from" => ^drawer}}, 500

      Server.minigame_stroke_end(slug, drawer, %{"pts" => [1, 2], "color" => "#000"})
      assert_receive {:minigame_relay, :stroke_end, %{"from" => ^drawer}}, 500
      assert length(Server.minigame_state(slug).strokes) == 1

      Server.minigame_undo(slug, guesser)
      refute_receive {:minigame_relay, :undo, _}, 100
      Server.minigame_undo(slug, drawer)
      assert_receive {:minigame_relay, :undo, _}, 500
      assert Server.minigame_state(slug).strokes == []

      Server.minigame_stroke_end(slug, drawer, %{"pts" => [3]})
      assert_receive {:minigame_relay, :stroke_end, _}, 500
      Server.minigame_clear(slug, drawer)
      assert_receive {:minigame_relay, :clear, _}, 500
      assert Server.minigame_state(slug).strokes == []

      # Wrong guess feeds the room; right guess scores.
      Server.minigame_guess(slug, guesser, "g", "definitely-not-#{word}")
      assert_receive {:minigame_feed, _}, 500
      Server.minigame_guess(slug, guesser, "g", word)
      changed!()
      assert MapSet.member?(Server.minigame_state(slug).guessed, guesser)

      # Host skip → reveal; non-host next ignored; host next advances.
      Server.minigame_skip(slug, guesser)
      no_change!()
      Server.minigame_skip(slug, host.id)
      changed!()
      assert Server.minigame_state(slug).phase == :turn_reveal

      Server.minigame_next(slug, guesser)
      no_change!()
      Server.minigame_next(slug, host.id)
      changed!()
      assert Server.minigame_state(slug).phase in [:turn, :gameover]
    end

    test "presence sync: drawer drop starts grace, return clears it, others pruned",
         %{slug: slug, drawer: drawer, players: players} do
      others = players -- [drawer]

      Server.minigame_presence_sync(slug, others)
      changed!()
      assert Server.minigame_state(slug).drawer_away

      Server.minigame_presence_sync(slug, players)
      changed!()
      refute Server.minigame_state(slug).drawer_away

      [gone | stay] = others
      Server.minigame_presence_sync(slug, [drawer | stay])
      changed!()
      refute gone in Server.minigame_state(slug).players

      # Nothing to prune → no broadcast.
      Server.minigame_presence_sync(slug, [drawer | stay])
      no_change!()
    end

    test "casts against a non-minigame chamber are silent no-ops", %{slug: slug, host: host} do
      Chambers.set_activity(Chambers.find_by_slug(slug), "music")
      assert_receive {:activity_changed, "music"}, 500

      for cast <- [
            fn -> Server.minigame_select_game(slug, host.id, "pictionary") end,
            fn -> Server.minigame_set_config(slug, host.id, %{}) end,
            fn -> Server.minigame_start(slug, host.id, []) end,
            fn -> Server.minigame_to_lobby(slug, host.id) end,
            fn -> Server.minigame_choose_word(slug, host.id, "x") end,
            fn -> Server.minigame_guess(slug, host.id, "h", "x") end,
            fn -> Server.minigame_skip(slug, host.id) end,
            fn -> Server.minigame_next(slug, host.id) end,
            fn -> Server.minigame_submit(slug, host.id, %{}) end,
            fn -> Server.minigame_album_next(slug, host.id) end,
            fn -> Server.minigame_stroke(slug, host.id, %{}) end,
            fn -> Server.minigame_stroke_end(slug, host.id, %{}) end,
            fn -> Server.minigame_undo(slug, host.id) end,
            fn -> Server.minigame_clear(slug, host.id) end,
            fn -> Server.minigame_presence_sync(slug, []) end
          ] do
        cast.()
      end

      no_change!()
      assert Server.minigame_state(slug) == nil
    end
  end

  describe "gartic phone" do
    test "submit rotates books, host advances album to game over",
         %{slug: slug, host: host, players: players} do
      Server.minigame_select_game(slug, host.id, "gartic_phone")
      changed!()
      Server.minigame_start(slug, host.id, players)
      changed!()
      assert %State{phase: :play} = Server.minigame_state(slug)

      # Steps = n (3): write → draw → describe. Everyone submits each.
      for step <- 0..2 do
        payload =
          if rem(step, 2) == 0,
            do: %{"text" => "step #{step}"},
            else: %{"strokes" => [%{"pts" => [0.1, 0.2]}]}

        for p <- players do
          Server.minigame_submit(slug, p, payload)
          changed!()
        end
      end

      assert %State{phase: :album} = Server.minigame_state(slug)

      # Non-host can't flip pages; host flips through to the end.
      Server.minigame_album_next(slug, hd(players -- [host.id]))
      no_change!()

      Enum.reduce_while(1..20, nil, fn _, _ ->
        Server.minigame_album_next(slug, host.id)
        changed!()

        case Server.minigame_state(slug).phase do
          :gameover -> {:halt, :ok}
          _ -> {:cont, nil}
        end
      end)

      assert %State{phase: :gameover} = Server.minigame_state(slug)
    end
  end

  describe "two truths" do
    test "write → guess → reveal → next → game over", %{slug: slug, host: host, players: players} do
      Server.minigame_select_game(slug, host.id, "two_truths")
      changed!()
      Server.minigame_start(slug, host.id, players)
      changed!()
      assert %State{phase: :writing} = Server.minigame_state(slug)

      for p <- players do
        Server.minigame_submit(slug, p, %{"items" => ["lie", "t1", "t2"], "lie" => 0})
        changed!()
      end

      assert %State{phase: :guessing} = Server.minigame_state(slug)

      # Play every author's round: non-authors guess, host advances the reveal.
      Enum.reduce_while(1..10, nil, fn _, _ ->
        mg = Server.minigame_state(slug)

        if mg.phase == :gameover do
          {:halt, :ok}
        else
          author = Enum.at(mg.game_state.order, mg.game_state.current)

          for p <- players, p != author do
            Server.minigame_submit(slug, p, %{"lie_guess" => 1})
            changed!()
          end

          assert Server.minigame_state(slug).phase == :reveal
          Server.minigame_next(slug, host.id)
          # next only handles :turn_reveal; use skip for two-truths' reveal.
          Server.minigame_skip(slug, host.id)
          changed!()
          {:cont, nil}
        end
      end)

      assert %State{phase: :gameover} = Server.minigame_state(slug)
    end
  end
end
