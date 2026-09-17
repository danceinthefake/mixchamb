defmodule MixchambWeb.RetroLiveTest do
  use MixchambWeb.ConnCase, async: false

  alias Mixchamb.{Accounts, Chambers, Retro}

  setup do
    {:ok, user} = Accounts.create_anonymous_user()
    {:ok, chamber} = Chambers.create_chamber(user.id, "retro")
    {:ok, session} = Retro.start_session(chamber.id, %{title: "Sprint 4"})
    %{user: user, chamber: chamber, session: session}
  end

  test "a live (non-archived) retro is not reachable via the permalink", %{conn: conn} = ctx do
    assert {:error, {:live_redirect, %{to: "/"}}} =
             live(conn, ~p"/archives/retros/#{ctx.session.id}")
  end

  test "unknown id bounces too", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/"}}} =
             live(conn, ~p"/archives/retros/#{Ecto.UUID.generate()}")
  end

  test "renders an archived retro with chamber snapshot + team link", %{conn: conn} = ctx do
    %{session: session, chamber: chamber} = ctx
    {:ok, session} = Retro.set_team(session, "Payments")
    s = advance_to(session, "discuss")
    Retro.snapshot_chamber_archive(s, chamber)
    _ = advance_to(s, "archived")

    {:ok, view, html} = live(conn, ~p"/archives/retros/#{session.id}")
    assert html =~ "Archived retro"
    assert html =~ "From:"
    assert html =~ "archived "
    assert has_element?(view, ~s(a[href="/t/payments"]), "Payments")
    assert page_title(view) =~ "Sprint 4"
  end

  test "falls back to the chamber title when the retro has none", %{conn: conn} = ctx do
    {:ok, session} = Retro.set_title(ctx.session, nil)
    s = advance_to(session, "discuss")
    Retro.snapshot_chamber_archive(s, %{ctx.chamber | title: "Team room"})
    _ = advance_to(s, "archived")

    {:ok, view, _} = live(conn, ~p"/archives/retros/#{session.id}")
    assert page_title(view) =~ "Team room"
  end

  defp advance_to(%{status: target} = s, target), do: s

  defp advance_to(s, target) do
    {:ok, next} = Retro.advance_phase(s)
    advance_to(next, target)
  end
end
