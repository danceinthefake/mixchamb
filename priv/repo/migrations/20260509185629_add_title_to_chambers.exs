defmodule Mixchamb.Repo.Migrations.AddTitleToChambers do
  use Ecto.Migration

  def change do
    alter table(:chambers) do
      # Optional human-readable name set by the creator.
      # Falls back to the slug in the UI when nil.
      add :title, :text
    end
  end
end
