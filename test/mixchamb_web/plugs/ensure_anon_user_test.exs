defmodule MixchambWeb.Plugs.EnsureAnonUserTest do
  use MixchambWeb.ConnCase, async: false

  alias Mixchamb.Accounts
  alias MixchambWeb.Plugs.EnsureAnonUser

  setup %{conn: conn} do
    # The plug requires fetched session.
    conn =
      conn
      |> Plug.Test.init_test_session(%{})

    %{conn: conn}
  end

  describe "first request" do
    test "creates a fresh anonymous user and stashes the id in the session", %{conn: conn} do
      conn = EnsureAnonUser.call(conn, [])

      assert %{display_name: name} = conn.assigns.current_user
      assert is_binary(name)
      assert is_binary(get_session(conn, :user_id))
      assert get_session(conn, :user_id) == conn.assigns.current_user.id
      assert Accounts.get_anonymous_user(conn.assigns.current_user.id)
    end
  end

  describe "subsequent request with a session" do
    test "loads the existing user instead of creating a new one", %{conn: conn} do
      {:ok, user} = Accounts.create_anonymous_user()
      conn = put_session(conn, :user_id, user.id)

      conn = EnsureAnonUser.call(conn, [])

      assert conn.assigns.current_user.id == user.id
    end

    test "starts a fresh user when the stashed id no longer exists", %{conn: conn} do
      conn = put_session(conn, :user_id, Ecto.UUID.generate())
      conn = EnsureAnonUser.call(conn, [])

      assert is_binary(conn.assigns.current_user.id)
      refute conn.assigns.current_user.id == get_session(conn, :user_id) |> then(fn _ -> nil end)
      assert Accounts.get_anonymous_user(conn.assigns.current_user.id)
    end
  end
end
