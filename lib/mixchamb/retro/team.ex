defmodule Mixchamb.Retro.Team do
  @moduledoc """
  A team is a slug retros get tagged with so they can be found
  again at `/t/:slug` after the chamber that hosted them is gone.
  No owner, no members — knowing the slug is the whole access
  model, same as a chamber link. `name` is the text the host typed;
  `slug` is its normalised form and the lookup key.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @derive {LiveVue.Encoder, only: [:id, :slug, :name]}

  schema "teams" do
    field :slug, :string
    field :name, :string
    has_many :retro_sessions, Mixchamb.Retro.RetroSession
    timestamps(type: :utc_datetime)
  end

  @max_len 40

  @doc false
  def creation_changeset(team, attrs) do
    team
    |> cast(attrs, [:name])
    |> update_change(:name, &String.trim/1)
    |> validate_required([:name])
    |> validate_length(:name, max: @max_len)
    |> put_slug()
    |> validate_required([:slug])
    |> unique_constraint(:slug)
  end

  defp put_slug(changeset) do
    case get_change(changeset, :name) do
      nil -> changeset
      name -> put_change(changeset, :slug, slugify(name))
    end
  end

  @doc """
  `"Payments Team!"` → `"payments-team"`. Returns `""` when nothing
  survives, which `validate_required` then rejects.
  """
  def slugify(name) when is_binary(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
    |> String.slice(0, @max_len)
    |> String.trim("-")
  end
end
