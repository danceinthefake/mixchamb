defmodule Mixwave.Repo.Migrations.AddRecordingToChambers do
  use Ecto.Migration

  def change do
    alter table(:chambers) do
      # Creator toggles this to capture note events into
      # chamber_events. Default false — recording is opt-in.
      add :is_recording, :boolean, null: false, default: false
    end

    create table(:chamber_events, primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")

      add :chamber_id,
          references(:chambers, type: :binary_id, on_delete: :delete_all),
          null: false

      # Same shape as the in-memory replay events: instrument,
      # style, note/chord, octave_offset, phase, up_strum,
      # display_name, alias, user_id. JSONB keeps the schema
      # tolerant to future fields.
      add :payload, :map, null: false

      # Microsecond precision so we can replay rapid bursts with
      # tight inter-event timing.
      add :inserted_at, :utc_datetime_usec, null: false, default: fragment("now()")
    end

    # Ordered scan by chamber — what the "Play recording" button
    # query needs.
    create index(:chamber_events, [:chamber_id, :inserted_at])
  end
end
