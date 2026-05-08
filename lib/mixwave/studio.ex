defmodule Mixwave.Studio do
  @moduledoc """
  The Studio context — one global jam.

  All connected players share the topic `"studio:lobby"`. Note events
  fan out via `Phoenix.PubSub`. Presence is handled by
  `MixwaveWeb.Presence` directly inside the LiveView; the Studio
  context covers the note-broadcast half.

  `Mixwave.Studio.Room` is a supervised GenServer that holds the
  last N note events so a newly-joining client can replay the recent
  past instead of dropping into silence.
  """

  alias Mixwave.Studio.Room

  @topic "studio:lobby"

  def topic, do: @topic

  @doc """
  Subscribes the calling process to the studio's note events.
  """
  def subscribe do
    Phoenix.PubSub.subscribe(Mixwave.PubSub, @topic)
  end

  @doc """
  Broadcasts a note event to every subscribed process and stores it
  in the Room's recent-events buffer.
  """
  def broadcast_note(payload) do
    event = %{
      kind: :note,
      payload: payload,
      at: System.monotonic_time(:millisecond)
    }

    Room.record(event)
    Phoenix.PubSub.broadcast(Mixwave.PubSub, @topic, {:studio_note, event})
    :ok
  end

  @doc """
  Returns the recent-events buffer (newest last).
  """
  def recent_events, do: Room.recent_events()

  @doc """
  Returns events from the recent buffer within the last `seconds`
  seconds, oldest first. Powers the "replay last 30s" button.
  """
  def recent_events_within(seconds) when is_integer(seconds) do
    cutoff = System.monotonic_time(:millisecond) - seconds * 1000

    Room.recent_events()
    |> Enum.filter(fn e -> e.at >= cutoff end)
  end
end
