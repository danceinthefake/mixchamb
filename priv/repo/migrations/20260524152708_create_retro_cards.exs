defmodule Mixchamb.Repo.Migrations.CreateRetroCards do
  use Ecto.Migration

  # One row per brainstormed card. Cards belong to a column;
  # the column belongs to a session. author_user_id is nullable
  # for anonymous-user cards (parallel to anon poker votes);
  # author_alias snapshots the display alias at create-time so
  # the card display stays stable even if the user later
  # changes their alias mid-session (see spec §3).
  #
  # vote_count is denormalised — the per-user vote map lives in
  # Chambers.Server during the :voting phase only, and the
  # materialised count lands here when phase advances to
  # :discuss (spec §5). For sessions where voting_enabled is
  # false, vote_count stays 0 forever.
  def change do
    create table(:retro_cards, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :retro_session_id,
          references(:retro_sessions, type: :binary_id, on_delete: :delete_all),
          null: false

      add :retro_column_id,
          references(:retro_columns, type: :binary_id, on_delete: :delete_all),
          null: false

      add :body, :text, null: false

      add :author_user_id,
          references(:anonymous_users, type: :binary_id, on_delete: :nilify_all),
          null: true

      # Snapshot of author's display alias at card creation
      # time. Survives later alias changes + author user reap.
      add :author_alias, :string, null: false

      add :vote_count, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    # Most reads are "all cards for this session, grouped by
    # column". Composite index covers both axes.
    create index(:retro_cards, [:retro_session_id, :retro_column_id])

    # During :discuss the cards render sorted by vote_count
    # desc. Covering index avoids a sort.
    create index(:retro_cards, [:retro_session_id, :vote_count])
  end
end
