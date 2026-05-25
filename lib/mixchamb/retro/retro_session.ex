defmodule Mixchamb.Retro.RetroSession do
  @moduledoc """
  One retrospective held inside a chamber. A chamber hosts many
  retros over its lifetime (one per sprint, etc.); each is a
  separate row. See `features/retrospective.md` §7 for the
  durability boundary (cards + actions persisted, vote map
  ephemeral).
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses ~w(setup brainstorm reveal voting discuss archived)
  def statuses, do: @statuses

  # LiveVue uses Phoenix LiveView's change tracking by assign
  # name, so when `@retro_session` flips, the diff walks the old
  # value (which is this struct, before retro_view/1 converts it).
  # Declaring encodable fields explicitly keeps the diff safe;
  # nested associations are walked via their own @derive below.
  @derive {LiveVue.Encoder,
           only: [
             :id,
             :title,
             :status,
             :voting_enabled,
             :brainstorm_visible,
             :revealed_at,
             :archived_at,
             :chamber_slug_snapshot,
             :chamber_title_snapshot
           ]}

  schema "retro_sessions" do
    field :title, :string
    field :status, :string, default: "setup"
    field :voting_enabled, :boolean, default: false
    field :brainstorm_visible, :boolean, default: false
    field :revealed_at, :utc_datetime
    field :archived_at, :utc_datetime

    # Snapshots of the originating chamber, captured at archive
    # time so the past-retro view (/retro/:id) keeps context even
    # after chamber reaping NULLs out the chamber_id FK.
    field :chamber_slug_snapshot, :string
    field :chamber_title_snapshot, :string

    belongs_to :chamber, Mixchamb.Chambers.Chamber
    belongs_to :creator, Mixchamb.Accounts.AnonymousUser, foreign_key: :creator_user_id
    has_many :columns, Mixchamb.Retro.RetroColumn, foreign_key: :retro_session_id
    has_many :cards, Mixchamb.Retro.RetroCard, foreign_key: :retro_session_id
    has_many :action_items, Mixchamb.Retro.RetroActionItem, foreign_key: :retro_session_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def creation_changeset(session, attrs) do
    session
    |> cast(attrs, [
      :chamber_id,
      :title,
      :voting_enabled,
      :brainstorm_visible,
      :creator_user_id
    ])
    |> validate_required([:chamber_id])
    |> validate_length(:title, max: 80)
  end

  @doc """
  Snapshot fields captured at archive time so the retro stays
  self-describing after chamber reaping NULLs out the FK.
  """
  def archive_snapshot_changeset(session, attrs) do
    session
    |> cast(attrs, [:chamber_slug_snapshot, :chamber_title_snapshot, :creator_user_id])
  end

  @doc false
  def brainstorm_visible_changeset(session, attrs) do
    session
    |> cast(attrs, [:brainstorm_visible])
    |> validate_required([:brainstorm_visible])
  end

  @doc false
  def title_changeset(session, attrs) do
    session
    |> cast(attrs, [:title])
    |> validate_length(:title, max: 80)
  end

  @doc false
  def voting_enabled_changeset(session, attrs) do
    session
    |> cast(attrs, [:voting_enabled])
    |> validate_required([:voting_enabled])
  end

  @doc false
  def phase_changeset(session, attrs) do
    session
    |> cast(attrs, [:status, :revealed_at, :archived_at])
    |> validate_required([:status])
    |> validate_inclusion(:status, @statuses)
  end
end
