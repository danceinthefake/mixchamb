defmodule Mixwave.Banners do
  @moduledoc """
  Admin-broadcast system banners. Every connected LV subscribes
  to `topic/0`; when a new banner is set or the current one is
  cleared, the broadcast pushes the new value out so all sessions
  re-render the top strip without polling.

  Banners are stored in the `banners` table — every set creates
  a new row with an `expires_at`; `current_banner/0` returns the
  newest non-expired row, or `nil`.
  """

  import Ecto.Query

  alias Mixwave.Banners.Banner
  alias Mixwave.Repo

  @topic "system:banner"

  @doc "PubSub topic every browser LV subscribes to on mount."
  def topic, do: @topic

  @doc """
  Persists a new banner, broadcasts the change to all subscribers,
  and returns `{:ok, banner}` on success.

  `duration_minutes` is converted to a future `expires_at`. The
  banner stops being "current" the moment that time passes.
  """
  def set_banner(message, duration_minutes, admin_user)
      when is_binary(message) and is_integer(duration_minutes) and duration_minutes > 0 and
             is_binary(admin_user) do
    expires_at =
      DateTime.utc_now()
      |> DateTime.add(duration_minutes * 60, :second)

    %Banner{}
    |> Banner.changeset(%{
      message: message,
      expires_at: expires_at,
      inserted_by: admin_user
    })
    |> Repo.insert()
    |> tap(fn
      {:ok, banner} -> broadcast({:banner_changed, banner})
      _ -> :ok
    end)
  end

  @doc """
  Clears the active banner by expiring the most recent row.
  Returns `{:ok, banner}` or `{:ok, nil}` if there was nothing
  active to clear.
  """
  def clear_banner do
    case current_banner() do
      nil ->
        {:ok, nil}

      banner ->
        banner
        |> Banner.changeset(%{
          message: banner.message,
          expires_at: DateTime.utc_now(),
          inserted_by: banner.inserted_by
        })
        |> Repo.update()
        |> tap(fn
          {:ok, _} -> broadcast({:banner_changed, nil})
          _ -> :ok
        end)
    end
  end

  @doc """
  The active banner, or `nil`. Active = newest row whose
  `expires_at` is still in the future.
  """
  def current_banner do
    now = DateTime.utc_now()

    Banner
    |> where([b], b.expires_at > ^now)
    |> order_by([b], desc: b.inserted_at)
    |> limit(1)
    |> Repo.one()
  end

  defp broadcast(message) do
    Phoenix.PubSub.broadcast(Mixwave.PubSub, @topic, message)
  end
end
