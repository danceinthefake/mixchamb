defmodule Mixchamb.Retro.RetroCardComment do
  @moduledoc """
  Comment on a retro card. Free-text, 280-char cap, alias-tagged
  (snapshot at create time). Flat threading in v1 (no
  replies-to-comments). Editable + deletable by author during
  live phases; locked once the retro is archived.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @max_body 280

  @derive {LiveVue.Encoder,
           only: [
             :id,
             :retro_card_id,
             :body,
             :author_user_id,
             :author_alias,
             :author_display_name,
             :inserted_at,
             :updated_at
           ]}

  schema "retro_card_comments" do
    field :body, :string
    field :author_alias, :string
    field :author_display_name, :string

    belongs_to :card, Mixchamb.Retro.RetroCard, foreign_key: :retro_card_id
    belongs_to :author, Mixchamb.Accounts.AnonymousUser, foreign_key: :author_user_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def creation_changeset(comment, attrs) do
    comment
    |> cast(attrs, [
      :retro_card_id,
      :body,
      :author_user_id,
      :author_alias,
      :author_display_name
    ])
    |> validate_required([:retro_card_id, :body, :author_alias])
    |> update_change(:body, &normalize_body/1)
    |> validate_length(:body, min: 1, max: @max_body)
  end

  @doc false
  def body_changeset(comment, attrs) do
    comment
    |> cast(attrs, [:body])
    |> validate_required([:body])
    |> update_change(:body, &normalize_body/1)
    |> validate_length(:body, min: 1, max: @max_body)
  end

  defp normalize_body(nil), do: nil
  defp normalize_body(body) when is_binary(body), do: String.trim(body)
end
