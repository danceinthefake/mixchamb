defmodule Mixchamb.Repo.Migrations.CreateRetroSessionsAndColumns do
  use Ecto.Migration

  # Adds the persistent backbone for the Retrospective activity
  # (see features/retrospective.md §7). A chamber can host many
  # retros over its lifetime (one per sprint, etc.); each is a
  # row in retro_sessions. The four columns per session are
  # rows in retro_columns — kept as a separate table (rather
  # than a JSON array on the session) so the name can be
  # renamed during :setup without changing card foreign keys,
  # and so per-column queries (cards-in-column) are simple
  # joins. Both FKs cascade-delete with the parent chamber.
  def change do
    create table(:retro_sessions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :chamber_id,
          references(:chambers, type: :binary_id, on_delete: :delete_all),
          null: false

      # Optional human-set title for this retro ("Sprint 23
      # retro"). Nullable — host can leave it blank.
      add :title, :string

      # Phase machine value (see spec §1). Stored as a string;
      # validation lives in Mixchamb.Retro.RetroSession's
      # @statuses list. Default :setup so a newly-created session
      # lands the host in the column-customisation phase.
      add :status, :string, null: false, default: "setup"

      # Off by default per spec §5 — host opts in any time
      # before :discuss.
      add :voting_enabled, :boolean, null: false, default: false

      # Captured when phase advances :brainstorm -> :reveal so
      # late joiners can tell at a glance how stale the cards
      # are. NULL while in :setup/:brainstorm.
      add :revealed_at, :utc_datetime

      # Captured when phase advances :discuss -> :archived.
      # NULL while session is live.
      add :archived_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    # Driven by the chamber-history disclosure in chamber_live.ex.
    # "Most recent retros first" query is hot.
    create index(:retro_sessions, [:chamber_id, :inserted_at])

    create table(:retro_columns, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :retro_session_id,
          references(:retro_sessions, type: :binary_id, on_delete: :delete_all),
          null: false

      # Custom column name. Default seed at session creation is
      # "Good", "Bad", "Start", "Thanks" — host can rename each
      # inline during :setup only (spec §2).
      add :name, :string, null: false

      # 0..3 — position drives the left-to-right render order
      # in RetroColumn.vue. Fixed at 4 columns in v1.
      add :position, :integer, null: false

      timestamps(type: :utc_datetime)
    end

    # Loading all columns for a session is the per-render hot
    # path; position ordering is part of the query.
    create index(:retro_columns, [:retro_session_id, :position])
  end
end
