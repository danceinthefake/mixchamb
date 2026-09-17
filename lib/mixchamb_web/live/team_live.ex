defmodule MixchambWeb.TeamLive do
  @moduledoc """
  A team's retro history at `/t/:slug`: every archived retro tagged
  with the team, newest-first, each linking to its permanent
  `/archives/retros/:id` view. No chamber GenServer involved — this
  is a plain read of Postgres, so it works long after the chambers
  that hosted the retros are gone.
  """
  use MixchambWeb, :live_view

  alias Mixchamb.Retro

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    case Retro.get_team_by_slug(slug) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "No team with that slug.")
         |> push_navigate(to: ~p"/")}

      team ->
        {:ok,
         socket
         |> assign(:team, team)
         |> assign(:sessions, Retro.list_team_sessions(team.id))
         |> assign(:open_actions, Retro.open_team_action_items(team.id))
         |> assign(:summary, Retro.team_summary(team.id))
         |> assign(:page_title, "#{team.name} · retros · mixchamb")}
    end
  end

  # Out-of-band completion (spec §13): anyone with the slug can tick
  # an item off between retros. Re-checked against the team's open
  # set so a hand-crafted id can't reach another team's rows.
  @impl true
  def handle_event("complete_action", %{"action_id" => action_id}, socket) do
    case Enum.find(socket.assigns.open_actions, &(&1.id == action_id)) do
      nil ->
        {:noreply, socket}

      item ->
        {:ok, _} = Retro.complete_previous_action_item(item)
        team_id = socket.assigns.team.id

        {:noreply,
         socket
         |> assign(:open_actions, Retro.open_team_action_items(team_id))
         |> assign(:summary, Retro.team_summary(team_id))}
    end
  end

  attr :label, :string, required: true
  attr :value, :any, required: true

  defp stat(assigns) do
    ~H"""
    <div class="rounded-xl border bg-card px-3 py-2">
      <dt class="text-[11px] uppercase tracking-wider text-muted-foreground font-display">
        {@label}
      </dt>
      <dd class="text-xl font-bold tabular-nums font-display">{@value}</dd>
    </div>
    """
  end

  defp completion_label(_done, 0), do: "—"
  defp completion_label(done, total), do: "#{done}/#{total} · #{div(done * 100, total)}%"

  defp session_counts(nil), do: "0 cards"

  defp session_counts(%{cards: cards, actions: actions, done: done}) do
    base = "#{cards} card#{if cards == 1, do: "", else: "s"}"
    if actions == 0, do: base, else: "#{base} · #{done}/#{actions} actions done"
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="max-w-3xl mx-auto px-4 py-6 space-y-6">
        <%!-- Remember this team in the browser so the landing page can
             offer it back (§7a step 12). Most-recent first, capped. --%>
        <div
          id="remember-team"
          phx-hook=".RememberTeam"
          phx-update="ignore"
          data-slug={@team.slug}
          data-name={@team.name}
          hidden
        >
        </div>
        <script :type={Phoenix.LiveView.ColocatedHook} name=".RememberTeam">
          export default {
            mounted() {
              const { slug, name } = this.el.dataset
              let teams = []
              try {
                teams = JSON.parse(localStorage.getItem("mixchamb:teams") || "[]")
              } catch (_) {}
              if (!Array.isArray(teams)) teams = []
              teams = [{ slug, name }, ...teams.filter((t) => t && t.slug !== slug)].slice(0, 8)
              try {
                localStorage.setItem("mixchamb:teams", JSON.stringify(teams))
              } catch (_) {}
            },
          }
        </script>

        <header class="space-y-1">
          <p class="text-xs uppercase tracking-wider text-muted-foreground font-display">
            Team
          </p>
          <h1 class="text-2xl font-bold tracking-tight font-display">{@team.name}</h1>
          <p class="text-xs text-muted-foreground">
            Retros tagged <code class="font-mono">{@team.slug}</code> land here. Type the same
            team name on your next retro's setup screen to keep the history in one place.
          </p>
        </header>

        <dl
          :if={@sessions != []}
          id="team-summary"
          class="grid grid-cols-2 sm:grid-cols-4 gap-2 text-center"
        >
          <.stat label="Retros" value={length(@sessions)} />
          <.stat label="Cards" value={@summary.cards} />
          <.stat label="Action items" value={@summary.actions} />
          <.stat
            label="Completed"
            value={completion_label(@summary.done, @summary.actions)}
          />
        </dl>

        <section :if={@open_actions != []} id="team-open-actions" class="space-y-2">
          <h2 class="text-sm uppercase tracking-wider text-muted-foreground font-display">
            Open action items · {length(@open_actions)}
          </h2>
          <ul class="divide-y rounded-xl border bg-card">
            <li
              :for={a <- @open_actions}
              id={"team-action-#{a.id}"}
              class="flex flex-wrap items-center gap-x-3 gap-y-1 px-4 py-2.5"
            >
              <div class="flex-1 min-w-0 text-sm">
                <p class="break-words">{a.body}</p>
                <p class="text-xs text-muted-foreground">
                  <span :if={a.assignee_alias}>{a.assignee_alias} · </span>
                  <span :if={a.due_date}>due {a.due_date} · </span>
                  from {a.session.title || "Untitled retro"}
                </p>
              </div>
              <button
                type="button"
                phx-click="complete_action"
                phx-value-action_id={a.id}
                class="rounded-md border px-2.5 py-1 text-xs font-medium hover:bg-accent shrink-0"
              >
                Mark done
              </button>
            </li>
          </ul>
        </section>

        <p
          :if={@sessions == []}
          id="team-empty"
          class="rounded-xl border bg-card p-6 text-sm text-muted-foreground italic"
        >
          No archived retros yet. Archive one and it shows up here.
        </p>

        <ol :if={@sessions != []} id="team-retros" class="divide-y rounded-xl border bg-card">
          <li :for={s <- @sessions} id={"team-retro-#{s.id}"}>
            <.link
              navigate={~p"/archives/retros/#{s.id}"}
              class="flex items-baseline justify-between gap-4 px-4 py-3 hover:bg-accent/40 transition-colors"
            >
              <span class="font-medium truncate">{s.title || "Untitled retro"}</span>
              <span class="text-xs text-muted-foreground tabular-nums whitespace-nowrap">
                {session_counts(@summary.per_session[s.id])} · {s.archived_at &&
                  Calendar.strftime(s.archived_at, "%Y-%m-%d")}
              </span>
            </.link>
          </li>
        </ol>
      </div>
    </Layouts.app>
    """
  end
end
