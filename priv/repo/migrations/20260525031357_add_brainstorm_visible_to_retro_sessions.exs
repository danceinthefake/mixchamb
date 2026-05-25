defmodule Mixchamb.Repo.Migrations.AddBrainstormVisibleToRetroSessions do
  use Ecto.Migration

  # Opt-in "show all cards during :brainstorm" mode. Default
  # false preserves the hidden-until-reveal behaviour every
  # existing retro session was started under (see
  # features/retrospective.md §4). Host picks at :setup only;
  # locked once Start brainstorm fires, same gate as column
  # rename.
  def change do
    alter table(:retro_sessions) do
      add :brainstorm_visible, :boolean, null: false, default: false
    end
  end
end
