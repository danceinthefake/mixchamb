defmodule Mixchamb.Repo.Migrations.CreateRetroActionItems do
  use Ecto.Migration

  # Action items captured during :discuss. Optionally tied to
  # a source card via source_card_id (spec §6) — when set, the
  # action renders nested under that card; nullable for
  # freeform actions. assignee_alias is plain text (not an FK)
  # since teams sometimes assign to people not in the chamber.
  #
  # created_by_user_id is captured for audit but not surfaced
  # in v1 UI. Both author/source FKs use nilify_all because
  # losing the linkage shouldn't delete the action — the
  # action's body is the durable record.
  def change do
    create table(:retro_action_items, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :retro_session_id,
          references(:retro_sessions, type: :binary_id, on_delete: :delete_all),
          null: false

      add :source_card_id,
          references(:retro_cards, type: :binary_id, on_delete: :nilify_all),
          null: true

      add :body, :text, null: false

      add :assignee_alias, :string

      add :due_date, :date

      add :completed, :boolean, null: false, default: false

      add :created_by_user_id,
          references(:anonymous_users, type: :binary_id, on_delete: :nilify_all),
          null: true

      timestamps(type: :utc_datetime)
    end

    # Loading all actions for a session is the hot path
    # (rendered during :discuss and on the archived view).
    create index(:retro_action_items, [:retro_session_id])

    # Looking up actions tied to a specific card is the second
    # hot path (rendered nested under each card in :discuss).
    create index(:retro_action_items, [:source_card_id])
  end
end
