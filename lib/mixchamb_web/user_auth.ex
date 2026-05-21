defmodule MixchambWeb.UserAuth do
  @moduledoc """
  LiveView authentication helpers.

  The HTTP-side plug (`MixchambWeb.Plugs.EnsureAnonUser`) creates the
  anonymous user before any page renders, so by the time a LiveView
  WebSocket connects, the session already carries `user_id`. This
  module's `on_mount` callback pulls that id back into a struct in
  the LV socket assigns.
  """
  import Phoenix.Component, only: [assign: 3]

  alias Mixchamb.Accounts

  @doc """
  on_mount callback. Wire into a LiveView with:

      use MixchambWeb, :live_view
      on_mount {MixchambWeb.UserAuth, :current_user}

  Or, more commonly, attach to a `live_session` in the router so a
  whole group of LVs share it.
  """
  def on_mount(:current_user, _params, %{"user_id" => user_id}, socket)
      when is_binary(user_id) do
    user = Accounts.get_anonymous_user(user_id)
    {:cont, assign(socket, :current_user, user)}
  end

  def on_mount(:current_user, _params, _session, socket) do
    # Shouldn't happen in normal flow — every browser request runs
    # through EnsureAnonUser before the LV mounts. Mount with nil
    # user rather than crashing so the page at least renders.
    {:cont, assign(socket, :current_user, nil)}
  end

  # `:current_admin` variant — wired into the :admin live_session
  # in the router. Pulls `:admin_username` out of the session
  # into the LV's `:current_admin` assign so handlers can
  # attribute audit rows to the human (or env break-glass user)
  # who's logged in.
  def on_mount(:current_admin, _params, %{"admin_username" => username}, socket)
      when is_binary(username) do
    {:cont, assign(socket, :current_admin, username)}
  end

  def on_mount(:current_admin, _params, _session, socket) do
    # Should never happen — AdminAuth blocks the request before
    # the LV mounts. Fall back to the env user so an audit row
    # never carries nil.
    fallback = Application.get_env(:mixchamb, :admin_user, "admin")
    {:cont, assign(socket, :current_admin, fallback)}
  end

  # `:maybe_admin` variant — for public LVs (e.g. ChamberLive) that
  # aren't behind AdminAuth but want to grant admins extra
  # capabilities. Assigns the admin username if there's an admin
  # session, nil otherwise. Use `is_binary(@current_admin)` as the
  # is-admin check in templates / handlers.
  def on_mount(:maybe_admin, _params, %{"admin_username" => username}, socket)
      when is_binary(username) do
    {:cont, assign(socket, :current_admin, username)}
  end

  # Stale-session fallback: sessions created before `admin_username`
  # was added still carry `admin_authenticated => true`. Treat those
  # as the env break-glass user so they keep their admin powers
  # until next login.
  def on_mount(:maybe_admin, _params, %{"admin_authenticated" => true}, socket) do
    fallback = Application.get_env(:mixchamb, :admin_user, "admin")
    {:cont, assign(socket, :current_admin, fallback)}
  end

  def on_mount(:maybe_admin, _params, _session, socket) do
    {:cont, assign(socket, :current_admin, nil)}
  end
end
