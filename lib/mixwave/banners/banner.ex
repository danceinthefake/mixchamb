defmodule Mixwave.Banners.Banner do
  @moduledoc """
  A system-wide message the admin broadcasts to every connected
  session. One row per broadcast; the "current banner" is the
  most recent row whose `expires_at` hasn't passed yet.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "banners" do
    field :message, :string
    field :expires_at, :utc_datetime_usec
    field :inserted_by, :string
    field :inserted_at, :utc_datetime_usec, autogenerate: {DateTime, :utc_now, []}
  end

  @doc false
  def changeset(banner, attrs) do
    banner
    |> cast(attrs, [:message, :expires_at, :inserted_by])
    |> validate_required([:message, :expires_at, :inserted_by])
    |> validate_length(:message, min: 1, max: 280)
  end
end
