defmodule Mixwave.Repo.Migrations.CreateAdminActionsAndBanners do
  use Ecto.Migration

  def change do
    # Audit trail for every action the admin LV performs against
    # the running system — kills, force-expires, drains, banner
    # broadcasts, etc. Append-only; no FK back to chambers /
    # users so the row survives the thing it acted on.
    create table(:admin_actions, primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      # Verb-style action name: "kill_chamber", "delete_user",
      # "drain_node", "broadcast", "run_sweeper", etc.
      add :action, :text, null: false
      # Free-form identifier of what was acted on, e.g.
      # "chamber:funky-meerkat" or "node:mixwave1@hostname".
      add :target, :text
      # Whoever was authenticated when the action fired (the env
      # ADMIN_USER value today; a real per-admin username once
      # admin auth is split up).
      add :admin_user, :text, null: false
      # Whatever extra context the handler wanted to record.
      add :metadata, :map, null: false, default: %{}
      add :inserted_at, :utc_datetime_usec, null: false, default: fragment("now()")
    end

    create index(:admin_actions, [:inserted_at])

    # System-wide banner the admin broadcasts to every connected
    # session. One row per broadcast; the "current banner" is the
    # most recent row whose expires_at hasn't passed yet.
    create table(:banners, primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :message, :text, null: false
      add :expires_at, :utc_datetime_usec, null: false
      add :inserted_by, :text, null: false
      add :inserted_at, :utc_datetime_usec, null: false, default: fragment("now()")
    end

    create index(:banners, [:expires_at])
  end
end
