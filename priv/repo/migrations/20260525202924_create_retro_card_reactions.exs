defmodule Mixchamb.Repo.Migrations.CreateRetroCardReactions do
  use Ecto.Migration

  # Multi-emoji reactions on retro cards. Each row is one
  # user's reaction with one emoji on one card; the unique
  # constraint (card, user, emoji) gives toggle behaviour
  # (re-clicking the same emoji removes the row). Users can
  # stack multiple emojis on the same card (a 👍 + ❤️ + 🎉
  # combo is one row each, three rows total).
  #
  # author_user_id nilifies on user reap so anon-user cleanup
  # doesn't delete the count. The visible chip stays even
  # after the user goes away; tooltip "who reacted" is a v2
  # polish.
  def change do
    create table(:retro_card_reactions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :retro_card_id,
          references(:retro_cards, type: :binary_id, on_delete: :delete_all),
          null: false

      add :user_id,
          references(:anonymous_users, type: :binary_id, on_delete: :nilify_all),
          null: true

      # Emoji literal stored verbatim (👍, ❤️, etc.). Validated
      # against a fixed allow-list in the schema — extending the
      # set is a code change, not a data migration.
      add :emoji, :string, null: false

      add :inserted_at, :utc_datetime, null: false
    end

    # Toggle uniqueness — one row per (card, user, emoji). Pre-
    # existing rows shrink when user un-reacts.
    create unique_index(:retro_card_reactions, [:retro_card_id, :user_id, :emoji])

    # Reading reactions for a card is the hot path (every render
    # of the card during :reveal / :voting / :discuss).
    create index(:retro_card_reactions, [:retro_card_id])
  end
end
