defmodule Mixchamb.Repo.Migrations.CreateRetroCardComments do
  use Ecto.Migration

  # Threaded discussion under each card. Flat threading in v1
  # (no replies-to-comments); same alias-snapshot pattern as
  # cards so the author identity survives anon-user reap.
  # 280-char cap mirrors cards.
  def change do
    create table(:retro_card_comments, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :retro_card_id,
          references(:retro_cards, type: :binary_id, on_delete: :delete_all),
          null: false

      add :body, :text, null: false

      add :author_user_id,
          references(:anonymous_users, type: :binary_id, on_delete: :nilify_all),
          null: true

      # Snapshot of (alias_or_name, display_name) at create
      # time — same convention as retro_cards.author_alias /
      # author_display_name. Lets the row stay self-describing
      # even after the author user reaps.
      add :author_alias, :string, null: false
      add :author_display_name, :string

      timestamps(type: :utc_datetime)
    end

    # Loading comments for a card is the hot path. Ordering by
    # inserted_at ascending so threads read top-to-bottom.
    create index(:retro_card_comments, [:retro_card_id, :inserted_at])
  end
end
