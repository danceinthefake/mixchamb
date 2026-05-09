defmodule MixwaveWeb.AdminSessionController do
  @moduledoc """
  Login + logout for the `/admin` section. Replaces HTTP Basic
  Auth (browser popup) with a proper session-backed form so the
  login UX matches the rest of the app.

  The credentials are still env-driven — `:admin_user` /
  `:admin_password` from `Application.get_env(:mixwave, ...)` —
  but on success we set `:admin_authenticated` in the session;
  `MixwaveWeb.Plugs.AdminAuth` checks that flag instead of the
  Authorization header.
  """
  use MixwaveWeb, :controller

  @doc """
  Renders the login form. If the user is already authenticated,
  short-circuits to the dashboard so a stale `/admin/login` URL
  doesn't show the form needlessly.
  """
  def new(conn, _params) do
    if get_session(conn, :admin_authenticated) do
      redirect(conn, to: ~p"/admin")
    else
      render(conn, :new, error: nil, username: "")
    end
  end

  @doc """
  Validates submitted credentials against the configured admin
  user/password. On success: regenerates the session id, flips
  the authenticated flag, redirects to `/admin`. On failure: re-
  renders the form with an error message and the entered username
  preserved.
  """
  def create(conn, %{"session" => %{"username" => user, "password" => pass}}) do
    if valid?(user, pass) do
      conn
      |> configure_session(renew: true)
      |> put_session(:admin_authenticated, true)
      |> put_flash(:info, "Welcome, admin.")
      |> redirect(to: ~p"/admin")
    else
      conn
      |> put_status(:unauthorized)
      |> render(:new, error: "Invalid username or password.", username: user)
    end
  end

  @doc """
  Drops the admin session flag and bounces home. Doesn't tear
  down the rest of the session (the anonymous user stays signed
  in for the regular app).
  """
  def delete(conn, _params) do
    conn
    |> delete_session(:admin_authenticated)
    |> put_flash(:info, "Logged out.")
    |> redirect(to: ~p"/")
  end

  defp valid?(user, pass) do
    expected_user = Application.get_env(:mixwave, :admin_user)
    expected_pass = Application.get_env(:mixwave, :admin_password)

    is_binary(expected_user) and is_binary(expected_pass) and expected_pass != "" and
      Plug.Crypto.secure_compare(user, expected_user) and
      Plug.Crypto.secure_compare(pass, expected_pass)
  end
end
