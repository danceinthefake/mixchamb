defmodule Mixchamb.Chambers.ChamberEvent do
  @moduledoc """
  One recorded note event for a chamber. Written by the chamber's
  GenServer when `chamber.is_recording == true`; read by the
  "Play recording" button to replay an entire session.

  `payload` mirrors the in-memory replay buffer's shape so the
  client's `replay_burst` Vue handler doesn't need a separate
  code path for live vs. persisted events:

      %{
        "instrument" => "drums",
        "style" => "synth",
        "note" => "kick",
        "chord" => nil,
        "octave_offset" => 0,
        "phase" => "down",
        "up_strum" => false,
        "user_id" => "<uuid>",
        "display_name" => "<noun-adj-NN>",
        "alias" => nil | "<user-set>"
      }

  Cascade-deletes with its chamber. No FK back to users — the
  payload carries the display name as a snapshot so the replay
  still attributes notes after the user is swept.
  """
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "chamber_events" do
    field :payload, :map
    field :inserted_at, :utc_datetime_usec, autogenerate: {DateTime, :utc_now, []}

    belongs_to :chamber, Mixchamb.Chambers.Chamber
  end
end
