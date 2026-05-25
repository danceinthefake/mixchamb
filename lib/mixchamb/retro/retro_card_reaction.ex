defmodule Mixchamb.Retro.RetroCardReaction do
  @moduledoc """
  One emoji reaction by one user on one retro card. The unique
  index on (card, user, emoji) gives toggle semantics; users
  can stack multiple emojis on the same card (one row per).

  Emoji set is fixed (allow-list below). Extending it is a code
  change rather than data validation living server-side.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @emojis ~w(👍 ❤️ 🎉 😄 😢 🤔)
  def emojis, do: @emojis

  @derive {LiveVue.Encoder,
           only: [:id, :retro_card_id, :user_id, :emoji, :inserted_at]}

  schema "retro_card_reactions" do
    field :emoji, :string
    field :inserted_at, :utc_datetime

    belongs_to :card, Mixchamb.Retro.RetroCard, foreign_key: :retro_card_id
    belongs_to :user, Mixchamb.Accounts.AnonymousUser, foreign_key: :user_id
  end

  @doc false
  def creation_changeset(reaction, attrs) do
    reaction
    |> cast(attrs, [:retro_card_id, :user_id, :emoji])
    |> validate_required([:retro_card_id, :user_id, :emoji])
    |> validate_inclusion(:emoji, @emojis)
    |> put_change(:inserted_at, DateTime.utc_now() |> DateTime.truncate(:second))
    |> unique_constraint([:retro_card_id, :user_id, :emoji])
  end
end
