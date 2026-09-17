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
         |> assign(:page_title, "#{team.name} · retros · mixchamb")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="max-w-3xl mx-auto px-4 py-6 space-y-6">
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
                {s.archived_at && Calendar.strftime(s.archived_at, "%Y-%m-%d")}
              </span>
            </.link>
          </li>
        </ol>
      </div>
    </Layouts.app>
    """
  end
end
