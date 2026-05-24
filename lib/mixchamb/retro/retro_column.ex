defmodule Mixchamb.Retro.RetroColumn do
  @moduledoc """
  One column within a retro session. Default seed names per
  spec §2: "Good", "Bad", "Start", "Thanks". Host can rename
  during `:setup` only — locked once brainstorm begins so cards
  written under one heading don't suddenly belong to another.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  # Default column names new sessions are seeded with. Host can
  # rename each inline during `:setup`. The four-column count
  # itself is fixed in v1.
  @default_names ~w(Good Bad Start Thanks)
  def default_names, do: @default_names

  @derive {LiveVue.Encoder, only: [:id, :name, :position]}

  schema "retro_columns" do
    field :name, :string
    field :position, :integer

    belongs_to :session, Mixchamb.Retro.RetroSession, foreign_key: :retro_session_id
    has_many :cards, Mixchamb.Retro.RetroCard, foreign_key: :retro_column_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def creation_changeset(column, attrs) do
    column
    |> cast(attrs, [:retro_session_id, :name, :position])
    |> validate_required([:retro_session_id, :name, :position])
    |> validate_length(:name, min: 1, max: 40)
    |> validate_number(:position, greater_than_or_equal_to: 0)
  end

  @doc false
  def rename_changeset(column, attrs) do
    column
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 40)
  end
end
