defmodule MixchambWeb.Admin.ChambersLive do
  @moduledoc """
  Admin → Chambers tab. Lists every chamber row with slug, title,
  kind, creator, lifecycle timestamps, presence count, and a force-
  delete action that bypasses the creator-only restriction.
  """
  use MixchambWeb, :live_view
  require Logger

  alias Mixchamb.Chambers
  alias Mixchamb.Chambers.Server, as: ChamberServer
  alias Mixchamb.RestartWatcher
  alias MixchambWeb.Admin.Layouts, as: AdminLayouts
  alias MixchambWeb.Presence
  import MixchambWeb.Admin.Format, only: [time_ago: 1]

  # Kept in sync with the keyframe in app.css.
  @flash_duration_ms 1_500

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Subscribe so the kill-row flash appears the instant a
      # chamber GenServer restarts, not on the next 2 s tick.
      Phoenix.PubSub.subscribe(Mixchamb.PubSub, RestartWatcher.topic())
      :timer.send_interval(2_000, :tick)
    end

    {:ok,
     socket
     |> assign(:search, "")
     |> assign(:chambers, load())}
  end

  @impl true
  def handle_info(:tick, socket) do
    {:noreply, assign(socket, :chambers, load())}
  end

  def handle_info(:restarts_changed, socket) do
    {:noreply, assign(socket, :chambers, load())}
  end

  @impl true
  def handle_event("search", %{"q" => query}, socket) do
    {:noreply, assign(socket, :search, query)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    case Mixchamb.Repo.get(Mixchamb.Chambers.Chamber, id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Chamber not found.")}

      %{slug: slug} = chamber ->
        Logger.warning("[admin/chambers] force-delete: slug=#{slug} id=#{id}")

        Mixchamb.Audit.log_as(socket.assigns.current_admin, "delete_chamber", "chamber:#{slug}", %{
          id: id
        })

        Chambers.delete(chamber)

        Phoenix.PubSub.broadcast(
          Mixchamb.PubSub,
          Chambers.topic(slug),
          {:chamber_closed, slug}
        )

        {:noreply,
         socket
         |> put_flash(:info, "Deleted chamber #{slug}.")
         |> assign(:chambers, load())}
    end
  end

  defp load do
    running = Chambers.list_running() |> Enum.into(%{})

    Chambers.list_all()
    |> Enum.map(fn c ->
      running? = Map.has_key?(running, c.slug)
      restart_count = Chambers.restart_count(c.slug)

      uptime_ms =
        if running? do
          case ChamberServer.info(c.slug) do
            %{uptime_ms: ms} -> ms
            _ -> nil
          end
        end

      %{
        id: c.id,
        slug: c.slug,
        title: c.title,
        kind: c.kind,
        creator_user_id: c.creator_user_id,
        activated_at: c.activated_at,
        last_activity_at: c.last_activity_at,
        inserted_at: c.inserted_at,
        running?: running?,
        presence_count: presence_count(c.slug),
        # Flash if the GenServer behind this row restarted within
        # the animation window. Same predicate the System tab uses
        # so a chaos kill flashes both views in lockstep.
        flashing?:
          running? and restart_count > 0 and is_integer(uptime_ms) and
            uptime_ms < @flash_duration_ms
      }
    end)
  end

  defp presence_count(slug) do
    Presence.list("chamber:#{slug}:presence") |> map_size()
  end

  # Case-insensitive substring filter on slug + title. Blank query
  # returns the full list unchanged so the user pays nothing when
  # they haven't typed anything. Title is nullable; fall through
  # to just the slug in that case.
  defp filter_chambers(chambers, ""), do: chambers

  defp filter_chambers(chambers, query) do
    q = query |> String.trim() |> String.downcase()

    if q == "" do
      chambers
    else
      Enum.filter(chambers, fn c ->
        String.contains?(String.downcase(c.slug), q) or
          (c.title && String.contains?(String.downcase(c.title), q))
      end)
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <AdminLayouts.admin_shell
      current_view={__MODULE__}
      flash={@flash}
      banner={assigns[:banner]}
      draining?={assigns[:draining?] || false}
    >
      <.header>
        Chambers
        <:subtitle>
          Every chamber in the DB. Force-delete bypasses the
          creator-only check on /chamber/:slug and broadcasts a
          close so any LV in that chamber redirects to the landing
          page.
        </:subtitle>
      </.header>

      <%!-- Search bar. phx-debounce keeps the change handler from
           firing on every keystroke; 200 ms is the standard fast-
           feedback latency. The filter is purely client-side
           against the already-loaded list (so a stale tick won't
           overwrite the search), and a blank query is a free
           no-op in `filter_chambers/2`. --%>
      <form
        :if={@chambers != []}
        phx-change="search"
        class="flex items-center gap-2"
      >
        <input
          type="text"
          name="q"
          value={@search}
          phx-debounce="200"
          placeholder="Filter by slug or title…"
          class="flex-1 bg-card border border-input rounded-md px-3 py-1.5 text-sm outline-none focus:border-primary/60"
        />
        <span class="text-xs text-muted-foreground tabular-nums whitespace-nowrap">
          {length(filter_chambers(@chambers, @search))} / {length(@chambers)}
        </span>
      </form>

      <div
        :if={@chambers == []}
        class="rounded-lg border border-dashed bg-card/50 p-8 text-center text-sm text-muted-foreground"
      >
        No chambers in the database yet.
      </div>

      <div
        :if={@chambers != [] and filter_chambers(@chambers, @search) == []}
        class="rounded-lg border border-dashed bg-card/50 p-8 text-center text-sm text-muted-foreground"
      >
        No chambers match <span class="font-mono">"{@search}"</span>.
      </div>

      <div
        :if={filter_chambers(@chambers, @search) != []}
        class="rounded-lg border bg-card overflow-hidden overflow-x-auto"
      >
        <table class="w-full text-sm">
          <thead class="bg-muted/40 text-xs uppercase tracking-wider text-muted-foreground">
            <tr class="text-left">
              <th class="px-4 py-2">Slug / Title</th>
              <th class="px-4 py-2">Kind</th>
              <th class="px-4 py-2">State</th>
              <th class="px-4 py-2 text-right">Present</th>
              <th class="px-4 py-2 text-right">Activity</th>
              <th class="px-4 py-2 text-right">Created</th>
              <th class="px-4 py-2"></th>
            </tr>
          </thead>
          <tbody class="divide-y">
            <tr
              :for={c <- filter_chambers(@chambers, @search)}
              class={["align-top", c.flashing? && "kill-flash"]}
            >
              <td class="px-4 py-3">
                <div class="flex items-center gap-2">
                  <%!-- Slug now links to the admin drill-down. The
                       small ↗ link beside it still opens the
                       user-facing chamber view. --%>
                  <.link
                    navigate={~p"/admin/chambers/#{c.slug}"}
                    class="font-mono text-xs font-medium hover:underline"
                  >
                    {c.slug}
                  </.link>
                  <.link
                    navigate={~p"/chamber/#{c.slug}"}
                    class="text-[10px] text-muted-foreground hover:text-foreground"
                    title="Open the user-facing chamber"
                  >
                    ↗
                  </.link>
                </div>
                <div class="text-xs text-muted-foreground truncate max-w-[18rem]">
                  {c.title || "(no title)"}
                </div>
              </td>
              <td class="px-4 py-3">
                <span class="text-xs px-2 py-0.5 rounded bg-muted text-muted-foreground font-mono">
                  {c.kind}
                </span>
              </td>
              <td class="px-4 py-3 text-xs">
                <span :if={c.creator_user_id == nil} class="text-amber-600 dark:text-amber-400">
                  system
                </span>
                <span
                  :if={c.creator_user_id != nil and c.activated_at}
                  class="text-emerald-600 dark:text-emerald-400"
                >
                  active
                </span>
                <span
                  :if={c.creator_user_id != nil and is_nil(c.activated_at)}
                  class="text-muted-foreground"
                >
                  grace
                </span>
                <span
                  :if={not c.running?}
                  class="ml-1 text-[10px] uppercase tracking-wider text-muted-foreground"
                >
                  no GenServer
                </span>
              </td>
              <td class="px-4 py-3 text-right tabular-nums">{c.presence_count}</td>
              <td class="px-4 py-3 text-right text-xs text-muted-foreground">
                {time_ago(c.last_activity_at)}
              </td>
              <td class="px-4 py-3 text-right text-xs text-muted-foreground">
                {time_ago(c.inserted_at)}
              </td>
              <td class="px-4 py-3 text-right">
                <.button
                  variant="outline"
                  phx-click="delete"
                  phx-value-id={c.id}
                  data-confirm={"Force-delete chamber #{c.slug}? Connected users get kicked back to the landing page."}
                  class="text-destructive hover:bg-destructive/10 hover:text-destructive"
                >
                  Delete
                </.button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </AdminLayouts.admin_shell>
    """
  end
end
