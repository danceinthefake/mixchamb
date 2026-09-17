defmodule Mixchamb.Repo.Migrations.AddMergedIntoToRetroCards do
  use Ecto.Migration

  # Card merge (features/retrospective.md §20). A merged card keeps
  # its row (author attribution, audit) but points at the card that
  # now represents it on the board. Deleting the target un-merges
  # its children rather than cascading.
  def change do
    alter table(:retro_cards) do
      add :merged_into_card_id,
          references(:retro_cards, type: :binary_id, on_delete: :nilify_all),
          null: true
    end

    create index(:retro_cards, [:merged_into_card_id])
  end
end
