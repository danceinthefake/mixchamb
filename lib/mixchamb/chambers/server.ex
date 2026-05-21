defmodule Mixchamb.Chambers.Server do
  @moduledoc """
  One GenServer per chamber, registered by slug via
  `Mixchamb.Chambers.Registry` and supervised by
  `Mixchamb.Chambers.Supervisor`.

  Holds the chamber's last N note events for join-time replay.
  Also owns the chamber lifecycle — the 30-minute grace-period
  self-check and the once-a-minute `last_activity_at` bump.

  `chamber_id` is the DB row's id — used by the lifecycle code to
  mark the chamber active or delete it. It's nilable so the
  GenServer can spin up before the persistence layer is wired in.

  The events buffer is intentionally not persisted — when the
  GenServer restarts, the jam resumes empty.
  """
  use GenServer

  @max_recent 200
  # Grace window during which the chamber must see a non-creator
  # join. If `activated_at` is still NULL when this elapses, the
  # GenServer deletes the chamber row and shuts itself down.
  @grace_period_ms 30 * 60 * 1000
  # How often the GenServer flushes the dirty flag to the DB by
  # bumping `last_activity_at`. Chosen for "rough enough that the
  # sweeper sees recent activity, cheap enough that it's not a
  # write per note even in busy chambers".
  @activity_bump_ms 60 * 1000
  # When recording is on, persisted events are buffered in memory
  # and flushed in batches. Whichever comes first wins.
  @recording_flush_interval_ms 2_000
  @recording_flush_batch_size 50

  ## Public API

  @doc """
  Returns the via-tuple for looking up a chamber's pid by slug.
  """
  def via(slug) when is_binary(slug) do
    {:via, Registry, {Mixchamb.Chambers.Registry, slug}}
  end

  @doc """
  Starts the GenServer for a slug under the dynamic supervisor if
  it isn't already running. Idempotent — returns the existing pid
  if a chamber with this slug is already up.
  """
  def ensure_started(slug, chamber_id \\ nil) when is_binary(slug) do
    case DynamicSupervisor.start_child(
           Mixchamb.Chambers.Supervisor,
           {__MODULE__, {slug, chamber_id}}
         ) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      err -> err
    end
  end

  def start_link({slug, chamber_id}) do
    GenServer.start_link(__MODULE__, %{slug: slug, chamber_id: chamber_id}, name: via(slug))
  end

  def child_spec({slug, _chamber_id} = args) do
    %{
      id: {__MODULE__, slug},
      start: {__MODULE__, :start_link, [args]},
      # `:transient` so the dynamic supervisor brings the chamber
      # back if it crashes (or if the supervisor LV's chaos button
      # kills it), but a clean `{:stop, :normal, _}` from the
      # grace-period delete still tears it down for good.
      restart: :transient
    }
  end

  @doc """
  Returns runtime info about a running chamber: pid, event count,
  uptime, and how many times its server has restarted in this BEAM.
  Used by the supervisor LV's per-chamber row.
  """
  def info(slug) when is_binary(slug) do
    GenServer.call(via(slug), :info, 1_000)
  catch
    :exit, _ -> nil
  end

  @doc """
  Records a note event in this chamber's buffer. When the chamber
  is recording, also enqueues the event's payload for the next
  bulk flush to `chamber_events`.
  """
  def record(slug, event), do: GenServer.cast(via(slug), {:record, event})

  @doc """
  Updates the in-memory recording flag. Called by
  `Mixchamb.Chambers.set_recording/2` after the DB row is updated
  so subsequent `record/2` calls know whether to enqueue.
  """
  def set_recording(slug, on?) when is_boolean(on?) do
    GenServer.cast(via(slug), {:set_recording, on?})
  end

  @doc """
  Returns the buffered events oldest-first.
  """
  def recent_events(slug), do: GenServer.call(via(slug), :recent_events)

  @doc """
  Returns events from the last `seconds` seconds, oldest-first.
  """
  def recent_events_within(slug, seconds) do
    GenServer.call(via(slug), {:recent_events_within, seconds})
  end

  ## GenServer

  @impl true
  def init(state) do
    # Schedule the grace-period check. If a non-creator joins
    # before this fires, ChamberLive flips activated_at on the
    # row; when the message arrives we re-read the row and only
    # delete if it's still NULL.
    if state.chamber_id do
      Process.send_after(self(), :check_grace, @grace_period_ms)
      Process.send_after(self(), :bump_activity, @activity_bump_ms)
    end

    # Bump the per-slug restart counter. Default `-1` so the very
    # first start lands at 0; subsequent restarts (after a chaos
    # kill) tick up from there. The supervisor LV reads this.
    count = :ets.update_counter(:chamber_restart_counts, state.slug, 1, {state.slug, -1})

    # Wake the supervisor LV immediately on a restart so its row
    # flashes red without waiting for the next 1 s polling tick.
    # First-time starts (count == 0) skip this — no flash to show.
    if count > 0 do
      Phoenix.PubSub.broadcast(
        Mixchamb.PubSub,
        Mixchamb.RestartWatcher.topic(),
        :restarts_changed
      )

      :telemetry.execute(
        [:mixchamb, :chamber, :restarted],
        %{count: 1},
        %{slug: state.slug, restart_count: count}
      )
    end

    started_at = System.monotonic_time(:millisecond)

    # Seed the recording flag from the DB so a chamber whose
    # creator turned REC on, then refreshed, keeps recording when
    # the GenServer is restarted.
    is_recording =
      case state.chamber_id && Mixchamb.Chambers.find_by_id(state.chamber_id) do
        %{is_recording: on?} -> on?
        _ -> false
      end

    if is_recording do
      Process.send_after(self(), :flush_recording, @recording_flush_interval_ms)
    end

    state =
      Map.merge(state, %{
        events: [],
        count: 0,
        dirty?: false,
        started_at: started_at,
        is_recording: is_recording,
        to_persist: []
      })

    {:ok, state}
  end

  @impl true
  def handle_cast({:record, event}, state) do
    events = [event | state.events] |> Enum.take(@max_recent)

    to_persist =
      if state.is_recording do
        [{event.payload, DateTime.utc_now()} | state.to_persist]
      else
        state.to_persist
      end

    new_state = %{
      state
      | events: events,
        count: state.count + 1,
        dirty?: true,
        to_persist: to_persist
    }

    # Threshold-flush right away so a busy chamber doesn't keep
    # an unbounded in-memory queue between timer ticks.
    new_state =
      if length(to_persist) >= @recording_flush_batch_size,
        do: flush_recording(new_state),
        else: new_state

    {:noreply, new_state}
  end

  def handle_cast({:set_recording, on?}, state) do
    cond do
      on? == state.is_recording ->
        {:noreply, state}

      on? == true ->
        Process.send_after(self(), :flush_recording, @recording_flush_interval_ms)
        {:noreply, %{state | is_recording: true}}

      true ->
        # Turning recording off — flush whatever's pending so we
        # don't lose the tail of the session.
        state = flush_recording(state)
        {:noreply, %{state | is_recording: false}}
    end
  end

  @impl true
  def handle_call(:info, _from, state) do
    uptime_ms = System.monotonic_time(:millisecond) - state.started_at
    {:reply, %{slug: state.slug, event_count: state.count, uptime_ms: uptime_ms}, state}
  end

  def handle_call(:recent_events, _from, state) do
    {:reply, Enum.reverse(state.events), state}
  end

  def handle_call({:recent_events_within, seconds}, _from, state) do
    cutoff = System.monotonic_time(:millisecond) - seconds * 1000

    events =
      state.events
      |> Enum.filter(&(&1.at >= cutoff))
      |> Enum.reverse()

    {:reply, events, state}
  end

  @impl true
  def handle_info(:check_grace, %{chamber_id: chamber_id, slug: slug} = state) do
    case Mixchamb.Chambers.find_by_id(chamber_id) do
      nil ->
        # Already deleted from DB out-of-band. Just terminate.
        {:stop, :normal, state}

      %{creator_user_id: nil} ->
        # System chamber (e.g., the public Chaos Chamber). No
        # creator means there's nothing to "wait for" — stays
        # alive forever.
        {:noreply, state}

      %{activated_at: nil} = chamber ->
        # Nobody but the creator showed up. Delete the row, tell
        # any subscribed LV to redirect, then shut down.
        Mixchamb.Chambers.delete(chamber)

        Phoenix.PubSub.broadcast(
          Mixchamb.PubSub,
          Mixchamb.Chambers.topic(slug),
          {:chamber_closed, slug}
        )

        {:stop, :normal, state}

      _activated ->
        # A non-creator joined within the grace window — chamber
        # stays alive. Nothing more to schedule.
        {:noreply, state}
    end
  end

  def handle_info(:flush_recording, state) do
    state = flush_recording(state)

    if state.is_recording do
      Process.send_after(self(), :flush_recording, @recording_flush_interval_ms)
    end

    {:noreply, state}
  end

  def handle_info(:bump_activity, %{chamber_id: chamber_id, dirty?: dirty?} = state) do
    # If notes came in this minute, flush a single DB write to
    # update last_activity_at. If nothing happened, skip the write
    # — the sweeper will eventually decide this chamber is idle.
    if dirty? do
      case Mixchamb.Chambers.find_by_id(chamber_id) do
        nil ->
          # Row deleted out-of-band (sweeper ran, or grace-period
          # delete fired). Stop the GenServer so we don't keep
          # trying to bump a non-existent row.
          {:stop, :normal, state}

        chamber ->
          Mixchamb.Chambers.touch_activity(chamber)
          Process.send_after(self(), :bump_activity, @activity_bump_ms)
          {:noreply, %{state | dirty?: false}}
      end
    else
      Process.send_after(self(), :bump_activity, @activity_bump_ms)
      {:noreply, state}
    end
  end

  @impl true
  def terminate(_reason, state) do
    # Flush any pending recording rows so a graceful shutdown
    # doesn't lose the tail of an active session.
    _ = flush_recording(state)
    :ok
  end

  # Drains `state.to_persist` to the DB in chronological order.
  # The queue is built head-first for O(1) prepend in handle_cast,
  # so we reverse before insert.
  defp flush_recording(%{to_persist: []} = state), do: state

  defp flush_recording(%{chamber_id: nil} = state) do
    # No chamber row to attach events to (system chamber created
    # before a chamber_id was wired in). Drop the queue.
    %{state | to_persist: []}
  end

  defp flush_recording(%{chamber_id: chamber_id, to_persist: queue} = state) do
    Mixchamb.Chambers.record_events(chamber_id, Enum.reverse(queue))
    %{state | to_persist: []}
  end
end
