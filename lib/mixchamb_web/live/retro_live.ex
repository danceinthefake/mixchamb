defmodule MixchambWeb.RetroLive do
  @moduledoc """
  Permanent read-only view of an archived retrospective. Mounted
  at `/archives/retros/:id`. Decoupled from any chamber GenServer (the
  chamber may have been reaped); just loads the session from
  Postgres and renders the Vue board in archived mode.
  """
  use MixchambWeb, :live_view

  alias Mixchamb.Retro
  alias MixchambWeb.ChamberLive

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Retro.get_archived_by_id(id) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Retro not found, or it isn't archived yet.")
         |> push_navigate(to: ~p"/")}

      session ->
        {:ok,
         socket
         |> assign(:retro_session, session)
         |> assign(:page_title, page_title_for(session))}
    end
  end

  defp page_title_for(session) do
    base = session.title || session.chamber_title_snapshot || "Retro"
    "#{base} · mixchamb"
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="max-w-6xl mx-auto px-4 py-6 space-y-4">
        <header class="space-y-1">
          <p class="text-xs uppercase tracking-wider text-muted-foreground font-display">
            Archived retro
          </p>
          <p
            :if={@retro_session.chamber_slug_snapshot || @retro_session.chamber_title_snapshot}
            class="text-xs text-muted-foreground"
          >
            From: {@retro_session.chamber_title_snapshot || @retro_session.chamber_slug_snapshot}
            <span :if={@retro_session.archived_at}>
              · archived {Calendar.strftime(@retro_session.archived_at, "%Y-%m-%d %H:%M UTC")}
            </span>
          </p>
          <p :if={@retro_session.team} class="text-xs text-muted-foreground">
            Team:
            <.link
              navigate={~p"/t/#{@retro_session.team.slug}"}
              class="underline underline-offset-2 hover:text-foreground"
            >
              {@retro_session.team.name}
            </.link>
            — all this team's retros
          </p>
        </header>

        <.RetroBoard
          chamber_slug={@retro_session.chamber_slug_snapshot || ""}
          session={ChamberLive.Retro.view(@retro_session)}
          tallies={%{}}
          my_votes={[]}
          discussing_card_id={nil}
          discussed={[]}
          timer_deadline={nil}
          timer_auto={false}
          participant_aliases={[]}
          previous_actions={[]}
          current_user_id=""
          current_user_alias=""
          is_host={false}
        />
      </div>
    </Layouts.app>
    """
  end
end
