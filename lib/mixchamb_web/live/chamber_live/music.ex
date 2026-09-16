defmodule MixchambWeb.ChamberLive.Music do
  @moduledoc """
  Music-activity half of `MixchambWeb.ChamberLive`: instrument
  switching, note fan-out, replay, recording, and the chamber's
  audio character (kind). `ChamberLive` routes the music events +
  PubSub messages here; the template stays in `ChamberLive`.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3, put_flash: 3]

  alias MixchambWeb.Presence
  alias Mixchamb.Chambers

  @instruments [:drums, :keyboard, :guitar, :bass, :pad, :suling, :kendang]
  @switch_cooldown_ms 1_000

  # Anti-flood guard on the `note` event. 20/sec/user is plenty of
  # headroom for human play (a fast drummer is ~10 hits/sec) and
  # caps automated spam decisively. Drops past the budget are
  # silent client-side; the server emits a telemetry event so the
  # admin Dashboard can show how many got shed.
  @note_rate_max 20
  @note_rate_window_ms 1_000

  @doc "Music assigns seeded on mount."
  def mount_assigns(socket, chamber, user) do
    socket
    |> assign(:instruments, @instruments)
    # Default to the user's last-played instrument so a return
    # visit doesn't always dump them on drums. Falls back to
    # :drums when no preference is stored or the stored value
    # is stale (no longer in @instruments). Music-only meaningful
    # but the assign sticks around for non-music chambers too —
    # it's just unused there.
    |> assign(:current_instrument, last_instrument_for(user))
    |> assign(:recorded_count, Chambers.recorded_event_count(chamber.id))
    # True between Stop Recording and either Download or Reset.
    # Drives a confirm dialog on Start Recording so the user
    # doesn't lose a recording they haven't saved yet.
    |> assign(:has_pending_audio, false)
    # Initialize so the first switch is never blocked. BEAM's
    # monotonic time can be a large negative integer at startup, so
    # `0` here would make the cooldown check (`now - last_switch_at`)
    # produce a negative result and reject every switch.
    |> assign(:last_switch_at, System.monotonic_time(:millisecond) - @switch_cooldown_ms)
    # {:expire_hit, ref} send_after; also capped at 5 so a drum roll
    # can't run away with the panel.
    |> assign(:recent_hits, [])

    # Mobile-only sheet that surfaces the presence panel's controls
    # (alias editor, host badges, promote / demote / step-down) on
  end

  @doc "Creator or any logged-in admin may change the chamber kind."
  def can_change_kind?(chamber, current_user, current_admin),
    do: chamber.creator_user_id == current_user.id or is_binary(current_admin)

  # ── Events ───────────────────────────────────────────────────────

  def handle_event("set_kind", %{"kind" => kind}, socket) do
    chamber = socket.assigns.chamber
    user = socket.assigns.current_user

    cond do
      not can_change_kind?(chamber, user, socket.assigns[:current_admin]) ->
        # Creators may change the kind on their own chamber; admins
        # may change it on any chamber (including the singleton chaos
        # chamber, which has no human creator they could ask). The
        # picker isn't rendered for everyone else; this guard is
        # for hand-crafted phx-events.
        {:noreply, socket}

      chamber.kind == kind ->
        # Already on this kind — skip the DB write + broadcast.
        {:noreply, socket}

      true ->
        case Chambers.set_kind(chamber, kind) do
          {:ok, updated} ->
            Phoenix.PubSub.broadcast(
              Mixchamb.PubSub,
              Mixchamb.Chambers.topic(chamber.slug),
              {:chamber_updated, updated}
            )

            {:noreply, assign(socket, :chamber, updated)}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, "Couldn't change the chamber type.")}
        end
    end
  end

  def handle_event("request_replay", _params, socket) do
    events = Mixchamb.Chambers.recent_events_within(socket.assigns.chamber_slug, 30)
    {:noreply, push_event(socket, "replay_burst", events_to_replay_payload(events))}
  end

  def handle_event("toggle_recording", _params, socket) do
    chamber = socket.assigns.chamber
    user = socket.assigns.current_user

    # Only the creator may toggle. Picker isn't rendered for
    # others, so the only path here is a hand-crafted phx-event.
    if chamber.creator_user_id != user.id do
      {:noreply, socket}
    else
      case Chambers.set_recording(chamber, !chamber.is_recording) do
        {:ok, updated} ->
          # Tell every subscribed client (including this LV) that
          # the chamber row changed — `handle_info({:chamber_updated, _})`
          # picks it up and re-renders the badge.
          Phoenix.PubSub.broadcast(
            Mixchamb.PubSub,
            Mixchamb.Chambers.topic(chamber.slug),
            {:chamber_updated, updated}
          )

          # Tell the creator's browser to start / stop tapping
          # Tone.Recorder so the live jam can be exported as audio.
          # push_event is per-socket, so only the creator (who
          # just clicked the toggle) sees these — non-creators
          # only get the chamber_updated broadcast.
          event_name =
            if updated.is_recording, do: "start_audio_capture", else: "stop_audio_capture"

          socket =
            socket
            |> push_event(event_name, %{})
            # Set the pending-audio flag based on the new state:
            # turning REC off means a blob is about to land (pending),
            # turning REC on means we just confirmed-and-replaced any
            # previous blob (no longer pending).
            |> assign(:has_pending_audio, not updated.is_recording)

          {:noreply, assign(socket, :chamber, updated)}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Couldn't toggle recording.")}
      end
    end
  end

  def handle_event("reset_recording", _params, socket) do
    chamber = socket.assigns.chamber
    user = socket.assigns.current_user

    cond do
      chamber.creator_user_id != user.id ->
        {:noreply, socket}

      chamber.is_recording ->
        # Refuse while recording is still on — would race with the
        # GenServer's batched flush. The button isn't rendered
        # in this state; this guard catches hand-crafted events.
        {:noreply, put_flash(socket, :error, "Stop recording before resetting.")}

      true ->
        {_count, _} = Chambers.delete_recorded_events(chamber.id)

        {:noreply,
         socket
         |> assign(:recorded_count, 0)
         |> assign(:has_pending_audio, false)
         |> push_event("clear_audio_capture", %{})}
    end
  end

  def handle_event("audio_downloaded", _params, socket) do
    # Vue's downloadLastRecording sends this so the LV can clear
    # the pending-audio flag — the user has saved the file, so
    # the overwrite-confirm on Start Recording shouldn't fire.
    {:noreply, assign(socket, :has_pending_audio, false)}
  end

  def handle_event("play_recording", _params, socket) do
    chamber = socket.assigns.chamber
    events = Chambers.recorded_events(chamber.id)
    {:noreply, push_event(socket, "replay_burst", recorded_to_replay_payload(events))}
  end

  def handle_event("note", payload, socket) do
    user = socket.assigns.current_user
    slug = socket.assigns.chamber_slug

    case Mixchamb.RateLimiter.hit(
           {:note, user.id, slug},
           @note_rate_max,
           @note_rate_window_ms
         ) do
      :ok ->
        payload
        |> Map.put("user_id", user.id)
        |> Map.put("display_name", user.display_name)
        |> Map.put("alias", user.alias)
        |> then(&Mixchamb.Chambers.broadcast_note(slug, &1))

        {:noreply, socket}

      :rate_limited ->
        :telemetry.execute(
          [:mixchamb, :chamber, :note_dropped],
          %{count: 1},
          %{slug: slug, user_id: user.id}
        )

        {:noreply, socket}
    end
  end

  def handle_event("switch_instrument", %{"to" => to}, socket) do
    instrument = String.to_existing_atom(to)
    now = System.monotonic_time(:millisecond)

    cond do
      instrument not in @instruments ->
        {:noreply, socket}

      now - socket.assigns.last_switch_at < @switch_cooldown_ms ->
        # Cooldown — ignore the request silently.
        {:noreply, socket}

      true ->
        user = socket.assigns.current_user
        slug = socket.assigns.chamber_slug

        Presence.update(self(), MixchambWeb.ChamberLive.presence_topic(slug), user.id, fn meta ->
          %{meta | instrument: instrument}
        end)

        # Remember the pick so the next chamber the user enters
        # opens on this instrument instead of the default drums.
        # `set_last_instrument` is a no-op when the value didn't
        # change, so coming back to the same pad doesn't burn
        # a DB write per switch.
        updated_user =
          case Mixchamb.Accounts.set_last_instrument(user, Atom.to_string(instrument)) do
            {:ok, u} -> u
            {:error, _} -> user
          end

        {:noreply,
         socket
         |> assign(:current_user, updated_user)
         |> assign(:current_instrument, instrument)
         |> assign(:last_switch_at, now)}
    end
  end

  # ── PubSub ───────────────────────────────────────────────────────

  def handle_info({:chamber_note, event}, socket) do
    user_id = socket.assigns.current_user.id

    # Append to the recent-hits feed shown in the presence aside,
    # for every hit (self + others). Releases don't show — only the
    # initial press counts as something the user "played".
    socket =
      case hit_label(event.payload) do
        nil ->
          socket

        label ->
          ref = System.unique_integer([:positive, :monotonic])
          # Pre-resolve the display name on the server so the
          # template doesn't have to reach back into @presences for
          # remote users (who may not even be in the presence map
          # yet during a join race).
          hit = %{
            ref: ref,
            user_name: hit_user_name(event.payload),
            label: label,
            instrument: hit_instrument_atom(event.payload),
            is_self: event.payload["user_id"] == user_id
          }

          Process.send_after(self(), {:expire_hit, ref}, 3500)
          assign(socket, :recent_hits, Enum.take([hit | socket.assigns.recent_hits], 5))
      end

    # Self-events skip the remote-play path: the player's local audio
    # already fired immediately on tap, so re-playing from the network
    # roundtrip would double-strike.
    if event.payload["user_id"] != user_id do
      {:noreply, push_event(socket, "play_remote_note", event.payload)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:expire_hit, ref}, socket) do
    {:noreply,
     assign(
       socket,
       :recent_hits,
       Enum.reject(socket.assigns.recent_hits, &(&1.ref == ref))
     )}
  end

  # Pull a human label out of the note payload. Each instrument
  # family puts the "what was played" value under a different key,
  # and pad release events have no label of their own (the press
  # already showed up). Drums and kendang send an explicit `label`
  # since their `note` field is a sample ID (e.g. `crash`) rather
  # than a displayable name (`Crash 1`).
  defp hit_label(%{"phase" => "release"}), do: nil
  defp hit_label(%{"label" => l}) when is_binary(l) and l != "", do: l
  defp hit_label(%{"chord" => c}) when is_binary(c), do: c
  defp hit_label(%{"note" => n}) when is_binary(n), do: n
  defp hit_label(%{"pad" => p}) when is_binary(p), do: p
  defp hit_label(_), do: nil

  defp hit_user_name(%{"alias" => a}) when is_binary(a) and a != "", do: a
  defp hit_user_name(%{"display_name" => n}) when is_binary(n), do: n
  defp hit_user_name(_), do: "Someone"

  # Map the instrument string from a network payload back to one of
  # @instruments. Unknown values collapse to :drums for the dot
  # colour — the label still renders correctly either way.
  defp hit_instrument_atom(%{"instrument" => i}) when is_binary(i) do
    try do
      atom = String.to_existing_atom(i)
      if atom in @instruments, do: atom, else: :drums
    rescue
      ArgumentError -> :drums
    end
  end

  defp hit_instrument_atom(_), do: :drums

  # Reads the user's stored last_instrument and normalises it back
  # to an atom against the @instruments allow-list. Returns :drums
  # when the field is nil, blank, or holds a stale value that's no
  # longer in the list (e.g. an instrument we removed in a later
  # release). String.to_existing_atom would crash on truly unknown
  # strings, so we route through it with a try/rescue.
  defp last_instrument_for(%{last_instrument: name}) when is_binary(name) and name != "" do
    try do
      atom = String.to_existing_atom(name)
      if atom in @instruments, do: atom, else: :drums
    rescue
      ArgumentError -> :drums
    end
  end

  defp last_instrument_for(_user), do: :drums

  ## Replay helpers

  # Trim the stored event buffer down to just the fields the Vue side
  # needs, with offsets relative to the first event so the client can
  # schedule them via setTimeout from "now."
  defp events_to_replay_payload([]), do: %{events: []}

  defp events_to_replay_payload([first | _] = events) do
    start_at = first.at

    events_payload =
      Enum.map(events, fn e ->
        replay_event(e.payload, e.at - start_at)
      end)

    %{events: events_payload}
  end

  # Same shape as `events_to_replay_payload/1` but starts from a
  # list of `Chambers.ChamberEvent` rows — these use absolute
  # `inserted_at` timestamps, so offsets are computed against the
  # first row's timestamp instead of monotonic time.
  defp recorded_to_replay_payload([]), do: %{events: []}

  defp recorded_to_replay_payload([first | _] = rows) do
    start_at = first.inserted_at

    events_payload =
      Enum.map(rows, fn row ->
        offset_ms = DateTime.diff(row.inserted_at, start_at, :millisecond)
        replay_event(row.payload, offset_ms)
      end)

    %{events: events_payload}
  end

  defp replay_event(payload, offset_ms) do
    %{
      instrument: payload["instrument"],
      style: payload["style"] || "synth",
      note: payload["note"],
      chord: payload["chord"],
      octave_offset: payload["octave_offset"] || 0,
      phase: payload["phase"],
      up_strum: payload["up_strum"],
      offset_ms: offset_ms
    }
  end
end
