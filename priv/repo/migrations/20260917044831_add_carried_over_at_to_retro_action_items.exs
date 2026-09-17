defmodule Mixchamb.Repo.Migrations.AddCarriedOverAtToRetroActionItems do
  use Ecto.Migration

  # Action-item carry-over (features/retrospective.md §13). An open
  # item from a team's previous retro can be copied into the current
  # one; the original is stamped rather than marked completed, so
  # "moved" and "done" stay distinguishable in the archive.
  def change do
    alter table(:retro_action_items) do
      add :carried_over_at, :utc_datetime
    end
  end
end
