defmodule Mixwave.Studio.Room do
  @moduledoc """
  Supervised GenServer holding per-room state: the last N note events.

  Used for two things: a newly-joining client replays the recent
  buffer so they don't drop into silence, and the "Replay 30 s"
  control reads from the same buffer.

  The buffer is intentionally not persisted — when this process
  restarts (after a crash or kill), the jam resumes empty.
  """
  use GenServer

  @max_recent 200

  ## Public API

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  def record(event), do: GenServer.cast(__MODULE__, {:record, event})

  def recent_events, do: GenServer.call(__MODULE__, :recent_events)

  ## GenServer

  @impl true
  def init(_opts) do
    # :queue from the stdlib gives O(1) push/pop at both ends; we use
    # a plain list and a counter for clarity over micro-optimization
    # at our scale (a few hundred events at most).
    {:ok, %{events: [], count: 0}}
  end

  @impl true
  def handle_cast({:record, event}, state) do
    events = [event | state.events] |> Enum.take(@max_recent)
    {:noreply, %{state | events: events, count: state.count + 1}}
  end

  @impl true
  def handle_call(:recent_events, _from, state) do
    {:reply, Enum.reverse(state.events), state}
  end
end
