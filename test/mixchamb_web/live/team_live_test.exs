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

  test "summary strip + per-retro counts", %{conn: conn, chamber: chamber} do
    {:ok, s} = Retro.start_session(chamber.id, %{title: "Sprint 1"})
    {:ok, s} = Retro.set_team(s, "stats")
    s = advance_to(s, "brainstorm")
    [col | _] = Retro.load_session(s.id).columns
    {:ok, _} = Retro.add_card(s, col, %{body: "a", author_alias: "x"})
    {:ok, _} = Retro.add_card(s, col, %{body: "b", author_alias: "x"})
    s = advance_to(s, "discuss")
    {:ok, done} = Retro.add_action_item(s, %{body: "done"})
    {:ok, _} = Retro.update_action_item(done, %{completed: true}, s)
    {:ok, _} = Retro.add_action_item(s, %{body: "open"})
    archive(s)

    {:ok, view, html} = live(conn, ~p"/t/stats")
    assert has_element?(view, "#team-summary")
    assert html =~ "2 cards · 1/2 actions done"
    assert html =~ "1/2 · 50%"

    # Ticking the open item off updates the strip.
    [open_item] = Retro.open_team_action_items(Retro.get_team_by_slug("stats").id)
    view |> element("#team-action-#{open_item.id} button") |> render_click()
    assert render(view) =~ "2/2 · 100%"
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
