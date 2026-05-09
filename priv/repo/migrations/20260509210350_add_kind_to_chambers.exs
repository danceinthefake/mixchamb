defmodule Mixwave.Repo.Migrations.AddKindToChambers do
  use Ecto.Migration

  def change do
    alter table(:chambers) do
      # Audio character of the chamber. Maps 1:1 to a preset in
      # the Tone.js master FX bus on the client. Stored as text;
      # the schema validates the inclusion list.
      add :kind, :text, null: false, default: "room"
    end
  end
end
