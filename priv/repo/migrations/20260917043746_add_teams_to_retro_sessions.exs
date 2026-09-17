defmodule Mixchamb.Repo.Migrations.AddTeamsToRetroSessions do
  use Ecto.Migration

  # Continuity without auth (BRAINSTORM-v4 §7a step 2). A team is
  # just a slug the host types on retro setup; every retro tagged
  # with it lists at /t/:slug and carries open action items
  # forward. No owner, no membership — the slug is a shared secret
  # like a chamber link.
  def change do
    create table(:teams, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :slug, :string, null: false
      add :name, :string, null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:teams, [:slug])

    alter table(:retro_sessions) do
      add :team_id, references(:teams, type: :binary_id, on_delete: :nilify_all), null: true
    end

    create index(:retro_sessions, [:team_id])
  end
end
