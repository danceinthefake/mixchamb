defmodule Mixchamb.Repo.Migrations.CreateChambers do
  use Ecto.Migration

  def change do
    create table(:chambers, primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      # Unguessable URL token. Generated as 8 random bytes
      # url-base64-encoded, ~11 chars, ~64 bits of entropy.
      add :slug, :text, null: false
      # The user who created the chamber. Nullable on delete so a
      # creator's account being reaped by the sweeper doesn't tear
      # down their (possibly active) chamber.
      add :creator_user_id, references(:anonymous_users, type: :binary_id, on_delete: :nilify_all)
      # Set the first time a non-creator joins. NULL = nobody else
      # has joined yet, so the chamber is still in its 5-minute
      # grace window and may auto-delete.
      add :activated_at, :utc_datetime

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:chambers, [:slug])
    # Used by the per-chamber GenServer to look up its row on init
    # without a full scan, and by any future cleanup sweep.
    create index(:chambers, [:inserted_at])
  end
end
