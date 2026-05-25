defmodule Mixchamb.Repo.Migrations.DecoupleRetroSessionsFromChambers do
  use Ecto.Migration

  # Make archived retros outlive their chambers (the chamber stays
  # ephemeral; the artefact survives).
  #
  # 1. retro_sessions.chamber_id FK flips from :delete_all to
  #    :nilify_all so chamber reap leaves the session row alone.
  # 2. Two snapshot columns capture chamber.slug + chamber.title
  #    at archive time — once the chamber is gone these are the
  #    only context the past-retro view has.
  # 3. creator_user_id snapshots the chamber's creator (a stable
  #    handle for "whose retro was this?" even after the chamber
  #    row goes away). Also nilify_all so anon-user reaping
  #    doesn't break orphaned retros.
  #
  # All three new columns are nullable: legacy rows from before
  # this migration genuinely don't have these values.
  def change do
    # `modify` with a `from:` clause emits the drop-and-recreate
    # of the existing FK constraint inline; no manual `drop
    # constraint` needed.
    alter table(:retro_sessions) do
      modify :chamber_id,
             references(:chambers, type: :binary_id, on_delete: :nilify_all),
             from: references(:chambers, type: :binary_id, on_delete: :delete_all),
             null: true

      add :chamber_slug_snapshot, :string
      add :chamber_title_snapshot, :string

      add :creator_user_id,
          references(:anonymous_users, type: :binary_id, on_delete: :nilify_all),
          null: true
    end

    # Cheap lookups for the "retros created by this anon user"
    # discovery path on the landing page (future feature; index
    # is cheap enough to add now).
    create index(:retro_sessions, [:creator_user_id])
  end
end
