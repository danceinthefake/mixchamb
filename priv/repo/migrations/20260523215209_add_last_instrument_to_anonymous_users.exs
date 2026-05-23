defmodule Mixchamb.Repo.Migrations.AddLastInstrumentToAnonymousUsers do
  use Ecto.Migration

  # Remembers which instrument the user last picked in a music
  # chamber, so coming back doesn't dump them on drums every time.
  # Wire format is the same atom string we already use in the
  # `switch_instrument` event payload (e.g. "keyboard", "bass") —
  # the LV reads it on mount and normalises to an atom against
  # the @instruments allow-list.
  def change do
    alter table(:anonymous_users) do
      add :last_instrument, :string
    end
  end
end
