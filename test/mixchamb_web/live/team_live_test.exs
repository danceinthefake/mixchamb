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

  test "lists open action items and marks one done", %{conn: conn, chamber: chamber} do
    {:ok, s} = Retro.start_session(chamber.id, %{title: "Sprint 1"})
    {:ok, s} = Retro.set_team(s, "ops")
    s = advance_to(s, "discuss")
    {:ok, item} = Retro.add_action_item(s, %{body: "rotate the pager"})
    archive(s)

    {:ok, view, _} = live(conn, ~p"/t/ops")
    assert has_element?(view, "#team-action-#{item.id}", "rotate the pager")

    view |> element("#team-action-#{item.id} button") |> render_click()
    refute has_element?(view, "#team-open-actions")
    assert Retro.get_action_item(item.id).completed
  end

  defp advance_to(%{status: target} = s, target), do: s

  defp advance_to(s, target) do
    {:ok, next} = Retro.advance_phase(s)
    advance_to(next, target)
  end

  defp archive(%{status: "archived"} = s), do: s

  defp archive(s) do
    {:ok, next} = Retro.advance_phase(s)
    archive(next)
  end
end
