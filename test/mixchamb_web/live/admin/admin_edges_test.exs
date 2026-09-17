defmodule MixchambWeb.Admin.AdminEdgesTest do
  @moduledoc "Admin tabs: tick / broadcast infos, error branches, and less-travelled rows."
  use MixchambWeb.ConnCase, async: false

  alias Mixchamb.{Accounts, Chambers}
  alias Mixchamb.Chambers.Server

  setup %{conn: conn} do
    conn =
      Plug.Test.init_test_session(conn, %{admin_authenticated: true, admin_username: "admin"})

    {:ok, user} = Accounts.create_anonymous_user()
    {:ok, chamber} = Chambers.create_chamber(user.id)
    %{conn: conn, user: user, chamber: chamber}
  end

  defp stop(slug) do
    case Registry.lookup(Mixchamb.Chambers.Registry, slug) do
      [{pid, _}] -> DynamicSupervisor.terminate_child(Mixchamb.Chambers.Supervisor, pid)
      _ -> :ok
    end
  end

  test "every polling tab survives a :tick and re-renders", %{conn: conn} do
    for path <-
          ~w(/admin /admin/system /admin/chambers /admin/sweepers /admin/health /admin/rate-limits /admin/ops) do
      {:ok, view, _} = live(conn, path)
      send(view.pid, :tick)
      assert render(view)
    end
  end

  test "ops: update_message echoes, banner_changed info, add_admin validation error, unknown admin",
       %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/admin/ops")
    assert render_hook(view, "update_message", %{"value" => "draft text"}) =~ "draft text"

    {:ok, banner} = Mixchamb.Banners.set_banner("from elsewhere", 15, "other-admin")
    send(view.pid, {:banner_changed, banner})

    assert render(view) =~ "from elsewhere"
    send(view.pid, {:banner_changed, nil})

    html = render_hook(view, "add_admin", %{"username" => "x", "password" => "short"})
    assert html =~ "password" or html =~ "username"

    assert render_hook(view, "delete_admin", %{"id" => Ecto.UUID.generate()}) =~ "Admin not found"
    assert render_hook(view, "clear_banner", %{}) =~ "Banner cleared"
  end

  test "chambers: delete a chamber (and an unknown id), restarts_changed + tick", %{
    conn: conn,
    chamber: chamber
  } do
    {:ok, view, _} = live(conn, ~p"/admin/chambers")
    send(view.pid, :restarts_changed)
    send(view.pid, :tick)
    assert render_hook(view, "delete", %{"id" => Ecto.UUID.generate()}) =~ "Chamber not found"
    html = render_hook(view, "delete", %{"id" => chamber.id})
    assert html =~ "Deleted chamber #{chamber.slug}"
    refute Chambers.find_by_slug(chamber.slug)
  end

  test "sweepers: run each sweeper, unknown key errors", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/admin/sweepers")
    assert render_hook(view, "run", %{"key" => "nope"}) =~ "Unknown sweeper"
    html = render_hook(view, "run", %{"key" => "chambers"})
    assert html =~ "deleted"
    html = render_hook(view, "run", %{"key" => "users"})
    assert html =~ "deleted"
  end

  test "system: restarts_changed, kill a running chamber, kill unknown module", %{
    conn: conn,
    chamber: chamber
  } do
    {:ok, _pid} = Server.ensure_started(chamber.slug, chamber.id)
    on_exit(fn -> stop(chamber.slug) end)
    {:ok, view, _} = live(conn, ~p"/admin/system")
    send(view.pid, :restarts_changed)
    assert render(view) =~ chamber.slug
    assert render_hook(view, "kill_chamber", %{"slug" => "no-such-chamber"})
    assert render_hook(view, "kill", %{"module" => "Elixir.Nope.Module"}) =~ "is not running"

    assert render_hook(view, "kill", %{"module" => "Elixir.Mixchamb.Chambers.Sweeper"}) =~
             "Killed"
  end

  test "chamber detail: presence rows, recording badge, system pill, broadcasts", %{
    conn: conn,
    chamber: chamber,
    user: user
  } do
    {:ok, chamber} = Chambers.set_recording(chamber, true)
    {:ok, _pid} = Server.ensure_started(chamber.slug, chamber.id)
    on_exit(fn -> stop(chamber.slug) end)

    # A real participant so the "Who's here" list has a row.
    user_conn = Plug.Test.init_test_session(build_conn(), %{"user_id" => user.id})
    {:ok, _member, _} = live(user_conn, ~p"/chamber/#{chamber.slug}")

    {:ok, view, html} = live(conn, ~p"/admin/chambers/#{chamber.slug}")
    assert html =~ user.display_name
    assert html =~ "on"
    send(view.pid, :tick)
    send(view.pid, %Phoenix.Socket.Broadcast{event: "presence_diff", payload: %{}, topic: "x"})
    send(view.pid, {:chamber_updated, %{chamber | title: "Renamed by broadcast"}})
    assert render(view) =~ "Renamed by broadcast"

    {:ok, chaos} = Chambers.ensure_chaos_chamber()
    {:ok, _} = Server.ensure_started(chaos.slug, chaos.id)
    on_exit(fn -> stop(chaos.slug) end)
    {:ok, _view, html} = live(conn, ~p"/admin/chambers/#{chaos.slug}")
    assert html =~ "system"
  end

  test "rate limits: saturated + dropped rows render", %{conn: conn, user: user, chamber: chamber} do
    for _ <- 1..25, do: Mixchamb.RateLimiter.hit({:note, user.id, chamber.slug}, 20, 60_000)

    :telemetry.execute([:mixchamb, :chamber, :note_dropped], %{count: 1}, %{
      slug: chamber.slug,
      user_id: user.id
    })

    {:ok, view, html} = live(conn, ~p"/admin/rate-limits")
    assert html =~ chamber.slug
    send(view.pid, :tick)
    assert render(view) =~ chamber.slug
  end
end
