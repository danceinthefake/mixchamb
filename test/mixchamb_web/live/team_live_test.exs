defmodule MixchambWeb.TeamLiveTest do
  use MixchambWeb.ConnCase, async: false

  alias Mixchamb.{Accounts, Chambers, Retro}

  setup do
    {:ok, user} = Accounts.create_anonymous_user()
    {:ok, chamber} = Chambers.create_chamber(user.id, "retro")
    %{user: user, chamber: chamber}
  end

  test "unknown slug bounces to landing", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/"}}} = live(conn, ~p"/t/nope")
  end

  test "lists a team's archived retros, newest first", %{conn: conn, chamber: chamber} do
    {:ok, s} = Retro.start_session(chamber.id, %{title: "Sprint 1"})
    {:ok, s} = Retro.set_team(s, "Payments Team")
    archive(s)

    {:ok, live_one} = Retro.start_session(chamber.id, %{title: "Sprint 2 (live)"})
    assert live_one.team.slug == "payments-team"

    {:ok, view, html} = live(conn, ~p"/t/payments-team")
    assert html =~ "Payments Team"
    assert has_element?(view, "#team-retros a", "Sprint 1")
    refute has_element?(view, "#team-retros a", "Sprint 2 (live)")
  end

  test "empty team shows the empty state", %{conn: conn, chamber: chamber} do
    {:ok, s} = Retro.start_session(chamber.id)
    {:ok, _} = Retro.set_team(s, "fresh")

    {:ok, view, _} = live(conn, ~p"/t/fresh")
    assert has_element?(view, "#team-empty")
  end

  defp archive(%{status: "archived"} = s), do: s

  defp archive(s) do
    {:ok, next} = Retro.advance_phase(s)
    archive(next)
  end
end
