defmodule Mixchamb.Audit.AdminAction do
  @moduledoc """
  One row per privileged action taken from the admin LV — kill,
  delete, drain, broadcast, sweeper run, etc. Append-only; no FK
  back to the affected row so the audit trail outlives the
  thing it acted on.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "admin_actions" do
    field :action, :string
    field :target, :string
    field :admin_user, :string
    field :metadata, :map, default: %{}
    field :inserted_at, :utc_datetime_usec, autogenerate: {DateTime, :utc_now, []}
  end

  @doc false
  def changeset(action, attrs) do
    action
    |> cast(attrs, [:action, :target, :admin_user, :metadata])
    |> validate_required([:action, :admin_user])
    |> validate_length(:action, max: 64)
  end
end
