defmodule MixchambWeb.Plugs.AdminAuth do
  @moduledoc """
  Session-backed gate for the `/admin/*` LiveView scope.

  An admin authenticates by submitting `MixchambWeb.AdminSessionController.create/2`
  (the `/admin/login` form). On success that controller flips
  `:admin_authenticated` in the session; this plug just checks
  for the flag and redirects unauthenticated requests to the
  login page.

  No password is checked here — credential validation happens
  exactly once in the session controller — but this plug does
  refuse the request when no admin password is configured at all,
  so a missing prod env fails closed instead of letting anyone
  who somehow has the session flag through.
  """
  import Plug.Conn
  import Phoenix.Controller, only: [redirect: 2, put_flash: 3]

  use MixchambWeb, :verified_routes

  def init(opts), do: opts

  def call(conn, _opts) do
    cond do
      not configured?() ->
        conn
        |> put_status(:service_unavailable)
        |> Phoenix.Controller.text("Admin password not configured.")
        |> halt()

      get_session(conn, :admin_authenticated) ->
        conn

      true ->
        conn
        |> put_flash(:error, "Please log in to access admin.")
        |> redirect(to: ~p"/admin/login")
        |> halt()
    end
  end

  defp configured? do
    pass = Application.get_env(:mixchamb, :admin_password)
    is_binary(pass) and pass != ""
  end
end
