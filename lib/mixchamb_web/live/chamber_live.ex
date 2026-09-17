defmodule MixchambWeb.ChamberLive do
  @moduledoc """
  The chamber view for a single chamber. Mounted at `/chamber/:slug`.

  On mount, looks up the chamber by slug. A missing or invalid
  slug pushes the user back to the landing page with a flash.
  Otherwise, ensures the chamber's GenServer is running and
  subscribes to its PubSub + presence topics.

  Wires:
    - `Mixchamb.Chambers.subscribe/1` for note-event broadcasts on
      this chamber's topic
    - `MixchambWeb.Presence` for "who's in this chamber, on what
      instrument"
    - 1-second server-side cooldown on instrument switch

  Instrument pads are Vue islands rendered inside a single
  `assets/vue/Chamber.vue` parent island. See that file for why
  pads aren't rendered as separate islands.
  """
  use MixchambWeb, :live_view

  import Bitwise

  alias MixchambWeb.Presence
  alias MixchambWeb.ChamberLive.{Music, Poker, Retro, MiniGame}
  alias Mixchamb.Chambers

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    case Chambers.find_by_slug(slug) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Chamber not found or already closed.")
         |> push_navigate(to: ~p"/")}

      chamber ->
        mount_chamber(chamber, socket)
    end
  end

  defp mount_chamber(chamber, socket) do
    user = socket.assigns.current_user
    slug = chamber.slug

    # Make sure a Chamber GenServer exists for this slug so calls
    # into Mixchamb.Chambers.* don't fail with :no_such_process. Safe
    # to call on every mount — idempotent if one is already up.
    {:ok, _pid} = Mixchamb.Chambers.Server.ensure_started(slug, chamber.id)

    # Record the visit so the user's next landing page shows this
    # chamber under "Resume". Swallow errors — visit tracking
    # mustn't block a chamber mount. Fire only on a connected
    # socket so we don't double-write during the dead-mount pass
    # (LV mounts twice: once stateless during HTTP, once over WS).
    if connected?(socket) do
      Chambers.touch_visit(user.id, chamber.id)
    end

    if connected?(socket) do
      Chambers.subscribe(slug)
      Phoenix.PubSub.subscribe(Mixchamb.PubSub, presence_topic(slug))

      {:ok, _} =
        Presence.track(self(), presence_topic(slug), user.id, %{
          display_name: user.display_name,
          alias: user.alias,
          instrument: :drums,
          joined_at: System.system_time(:second),
          node: Node.self()
        })

      # Mirror the join on a global "who's online + where" topic so
      # admin UsersLive can show node + chamber per user without
      # enumerating every chamber's presence topic.
      {:ok, _} =
        Presence.track(self(), "users:online", user.id, %{
          node: Node.self(),
          chamber: slug,
          joined_at: System.system_time(:second)
        })
    end

    presences =
      if connected?(socket),
        do: Presence.list(presence_topic(slug)),
        else: %{}

    {:ok,
     socket
     |> assign(:chamber, chamber)
     |> assign(:chamber_slug, slug)
     |> assign(:page_title, page_title_for(chamber))
     # Open Graph / Twitter card overrides — when someone shares
     # this chamber's URL, the link preview shows the chamber's
     # name and an activity-specific description instead of the
     # site-wide defaults in root.html.heex.
     |> assign(:og_title, chamber_og_title(chamber))
     |> assign(:og_description, chamber_og_description(chamber))
     |> assign(:og_url, url(~p"/chamber/#{slug}"))
     |> assign(:presences, presences)
     # Mobile-only sheet that surfaces the presence panel's controls
     # (alias editor, host badges, promote / demote / step-down) on
     # phones where the floating aside is `hidden lg:block`. Triggered
     # by tapping the dock's presence pill; default closed.
     |> assign(:presence_sheet_open, false)
     |> Music.mount_assigns(chamber, user)
     |> Poker.mount_assigns(chamber)
     |> Retro.mount_assigns(chamber, user)
     |> MiniGame.mount_assigns(chamber)
     |> assign_hosts(chamber, user)}
  end

  # Compute the host set + is_host flag from the chamber server's
  # ephemeral state. Falls back to creator-only if the server hasn't
  # initialised the hosts MapSet yet (very narrow startup race —
  # `hosts/1` would crash on a nil state field otherwise). The
  # creator is always implicitly in the set even on this fallback
  # path, so the original-creator-as-host invariant survives any
  # ordering quirk.
  defp assign_hosts(socket, chamber, user) do
    hosts =
      try do
        Mixchamb.Chambers.Server.hosts(chamber.slug)
      catch
        :exit, _ -> [chamber.creator_user_id]
      end

    hosts_set = MapSet.new(hosts)
    is_host = MapSet.member?(hosts_set, user.id)

    socket
    |> assign(:hosts, hosts_set)
    |> assign(:is_host, is_host)
  end

  # ── Activity routing ─────────────────────────────────────────────
  # Poker / retro / mini-game events are prefixed on the wire; music
  # events predate the multi-activity split and keep their bare
  # names. Everything else is chamber-shell (title, alias, hosts,
  # activity switch) and handled below.

  @music_events ~w(set_kind request_replay toggle_recording reset_recording
                   audio_downloaded play_recording note switch_instrument)

  @impl true
  def handle_event("poker_" <> _ = event, params, socket),
    do: Poker.handle_event(event, params, socket)

  def handle_event("retro_" <> _ = event, params, socket),
    do: Retro.handle_event(event, params, socket)

  def handle_event("minigame_" <> _ = event, params, socket),
    do: MiniGame.handle_event(event, params, socket)

  def handle_event(event, params, socket) when event in @music_events,
    do: Music.handle_event(event, params, socket)

  def handle_event("save_title", %{"title" => title}, socket) do
    chamber = socket.assigns.chamber
    user = socket.assigns.current_user

    # Only the creator may rename. Anyone else is silently ignored —
    # the input isn't even rendered for them, so the only path here
    # is a hand-crafted phx-event push.
    if chamber.creator_user_id != user.id do
      {:noreply, socket}
    else
      case Chambers.set_title(chamber, title) do
        {:ok, updated} ->
          # Broadcast so anyone else in the chamber sees the new
          # title without reloading.
          Phoenix.PubSub.broadcast(
            Mixchamb.PubSub,
            Mixchamb.Chambers.topic(chamber.slug),
            {:chamber_updated, updated}
          )

          {:noreply,
           socket
           |> assign(:chamber, updated)
           |> assign(:page_title, page_title_for(updated))}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Couldn't save the title.")}
      end
    end
  end

  @impl true
  def handle_event("set_alias", %{"alias" => value}, socket) do
    user = socket.assigns.current_user
    slug = socket.assigns.chamber_slug

    case Mixchamb.Accounts.set_alias(user, value) do
      {:ok, updated} ->
        # Re-track presence so other clients see the new alias
        # without needing to re-query the DB.
        Presence.update(self(), presence_topic(slug), updated.id, fn meta ->
          %{meta | alias: updated.alias}
        end)

        {:noreply, assign(socket, :current_user, updated)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Alias is too long (max 32 chars).")}
    end
  end

  # Creator promotes another participant to co-host. Server enforces
  # the creator-only rule independently; this LV-side check is the
  # fast path so a misclick on a stale UI doesn't burn a roundtrip.
  def handle_event("promote_host", %{"user_id" => target}, socket) when is_binary(target) do
    Mixchamb.Chambers.Server.promote_host(
      socket.assigns.chamber_slug,
      socket.assigns.current_user.id,
      target
    )

    {:noreply, socket}
  end

  # Demote: creator demotes anyone, co-host demotes self. Same dual
  # enforcement: server authoritative, LV just routes the cast.
  def handle_event("demote_host", %{"user_id" => target}, socket) when is_binary(target) do
    Mixchamb.Chambers.Server.demote_host(
      socket.assigns.chamber_slug,
      socket.assigns.current_user.id,
      target
    )

    {:noreply, socket}
  end

  # Mobile presence sheet open/close. The desktop aside stays
  # always-visible at `lg:` and up; this flag only drives the
  # `lg:hidden` overlay that mirrors the same content for phones.
  def handle_event("toggle_presence_sheet", _params, socket) do
    {:noreply, update(socket, :presence_sheet_open, &(not &1))}
  end

  # Host-only activity switch (music ↔ poker). Chaos chamber stays
  # music-locked — it has no human creator and the picker isn't
  # rendered for anyone but the creator anyway, so this guard is
  # belt-and-braces for hand-crafted phx events.
  def handle_event("set_activity", %{"activity" => activity}, socket)
      when is_binary(activity) do
    chamber = socket.assigns.chamber
    user = socket.assigns.current_user

    cond do
      chamber.creator_user_id != user.id ->
        {:noreply, socket}

      activity not in Mixchamb.Chambers.Chamber.activities() ->
        {:noreply, socket}

      chamber.activity == activity ->
        {:noreply, socket}

      true ->
        case Chambers.set_activity(chamber, activity) do
          {:ok, _updated} ->
            # The GenServer cast broadcasts {:activity_changed, _};
            # every LV (including this one) refreshes state in
            # handle_info below.
            {:noreply, socket}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, "Couldn't switch activity.")}
        end
    end
  end

  @impl true
  def handle_info({:poker, _, _} = msg, socket), do: Poker.handle_info(msg, socket)
  def handle_info({:poker, _, _, _, _} = msg, socket), do: Poker.handle_info(msg, socket)
  def handle_info({:retro, _, _} = msg, socket), do: Retro.handle_info(msg, socket)
  def handle_info({:retro, _, _, _} = msg, socket), do: Retro.handle_info(msg, socket)
  def handle_info({:retro, _, _, _, _} = msg, socket), do: Retro.handle_info(msg, socket)
  def handle_info({:retro, _, _, _, _, _} = msg, socket), do: Retro.handle_info(msg, socket)
  def handle_info({:minigame, _} = msg, socket), do: MiniGame.handle_info(msg, socket)
  def handle_info({:minigame_feed, _} = msg, socket), do: MiniGame.handle_info(msg, socket)
  def handle_info({:minigame_relay, _, _} = msg, socket), do: MiniGame.handle_info(msg, socket)
  def handle_info({:chamber_note, _} = msg, socket), do: Music.handle_info(msg, socket)
  def handle_info({:expire_hit, _} = msg, socket), do: Music.handle_info(msg, socket)

  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket) do
    presences = Presence.list(presence_topic(socket.assigns.chamber_slug))

    # Mini-game rotation reconciliation (spec §7). Only the host casts
    # so the drawer-left / player-left handling runs once, not once
    # per client; with no host present the game freezes, as designed.
    if socket.assigns.chamber.activity == "minigame" and socket.assigns.is_host do
      Mixchamb.Chambers.Server.minigame_presence_sync(
        socket.assigns.chamber_slug,
        Map.keys(presences)
      )
    end

    {:noreply,
     socket
     |> assign(:presences, presences)
     |> maybe_mark_active(presences)}
  end

  # Sent by the chamber's GenServer when it deletes itself because
  # the 30-minute grace period elapsed without anyone but the
  # creator joining.
  def handle_info({:chamber_closed, _slug}, socket) do
    {:noreply,
     socket
     |> put_flash(:info, "Chamber closed — nobody else joined within 30 minutes.")
     |> push_navigate(to: ~p"/")}
  end

  # Co-host promotion / demotion fans out to everyone in the chamber.
  # Each client recomputes its own is_host flag — the host-only
  # controls in the template will re-render accordingly within a
  # single LV diff.
  def handle_info({:hosts_changed, hosts}, socket) do
    hosts_set = MapSet.new(hosts)
    user_id = socket.assigns.current_user.id

    {:noreply,
     socket
     |> assign(:hosts, hosts_set)
     |> assign(:is_host, MapSet.member?(hosts_set, user_id))}
  end

  # Activity flipped by the host. Re-pull the chamber row so the
  # local `activity` assign matches the DB, then reload the
  # activity-specific session assigns (poker fresh / nil; retro
  # rehydrated from DB if a session exists).

  def handle_info({:activity_changed, activity}, socket) do
    chamber = Chambers.find_by_slug(socket.assigns.chamber_slug)

    {:noreply,
     socket
     |> assign(:chamber, chamber)
     |> Poker.mount_assigns(chamber)
     |> Retro.reload(chamber)
     |> MiniGame.mount_assigns(chamber)
     # Tell the room the host flipped the activity — the board swaps
     # underneath everyone, so a flash explains why. Fires for every
     # connected client (the host's own confirms their click).
     |> put_flash(:info, "Host switched the chamber to #{activity_label(activity)}.")}
  end

  # Broadcast by the LV that wrote the title change. Everyone else
  # in the chamber updates their assigns + page title.
  def handle_info({:chamber_updated, updated}, socket) do
    # Refresh recorded_count too — a REC-off transition makes the
    # newly-finalised session available for replay, and we need
    # the count to enable the Play button + render its label.
    {:noreply,
     socket
     |> assign(:chamber, updated)
     |> assign(:page_title, page_title_for(updated))
     |> assign(:recorded_count, Chambers.recorded_event_count(updated.id))}
  end

  @doc false
  def presence_topic(slug) when is_binary(slug), do: "chamber:#{slug}:presence"

  # Display helpers for the (alias, display_name) pair. The
  # auto-generated display_name is always shown somewhere; the
  # alias becomes the headline when set.
  defp alias_set?(%{alias: a}) when is_binary(a) and a != "", do: true
  defp alias_set?(_), do: false

  defp primary_name(%{alias: a} = _meta) when is_binary(a) and a != "", do: a
  defp primary_name(%{display_name: name}), do: name

  # Flips the chamber's `activated_at` from NULL to a timestamp
  # the first time someone other than the creator is present.
  # Idempotent: a no-op once the chamber is already active.
  defp maybe_mark_active(socket, presences) do
    chamber = socket.assigns.chamber

    cond do
      chamber.activated_at != nil ->
        socket

      non_creator_present?(presences, chamber) ->
        case Chambers.mark_active(chamber) do
          {:ok, updated} -> assign(socket, :chamber, updated)
          {:error, _} -> socket
        end

      true ->
        socket
    end
  end

  defp non_creator_present?(presences, chamber) do
    Enum.any?(presences, fn {user_id, _meta} ->
      user_id != chamber.creator_user_id
    end)
  end

  ## Render helpers

  defp activity_label("music"), do: "Music"
  defp activity_label("poker"), do: "Poker"
  defp activity_label("retro"), do: "Retro"
  defp activity_label("minigame"), do: "Mini-game"

  # Active-state class for each activity chip. Music carries the
  # brand pink (--primary); poker carries cyan (--accent-poker);
  # retro carries the bass accent so the chip-strip itself reads
  # which activity the chamber is in. Static class strings so
  # Tailwind picks them up at build time.
  defp activity_chip_active_class("music"),
    do: "bg-primary/15 text-primary border-primary/40"

  defp activity_chip_active_class("poker"),
    do: "bg-accent-poker/15 text-accent-poker border-accent-poker/40"

  defp activity_chip_active_class("retro"),
    do: "bg-accent-bass/15 text-accent-bass border-accent-bass/40"

  defp activity_chip_active_class("minigame"),
    do: "bg-accent-minigame/15 text-accent-minigame border-accent-minigame/40"

  defp chamber_og_title(%{activity: "poker"} = chamber),
    do: "Planning poker · #{chamber.title} · mixchamb"

  defp chamber_og_title(%{activity: "retro"} = chamber),
    do: "Retro · #{chamber.title} · mixchamb"

  defp chamber_og_title(%{activity: "minigame"} = chamber),
    do: "Mini-game · #{chamber.title} · mixchamb"

  defp chamber_og_title(chamber),
    do: "Jamming in #{chamber.title} · mixchamb"

  defp chamber_og_description(%{activity: "poker"} = chamber) do
    "Join the planning session in #{chamber.title}. Vote on stories, reveal together, anyone with the link can join."
  end

  defp chamber_og_description(%{activity: "retro"} = chamber) do
    "Join the retrospective in #{chamber.title}. Brainstorm, optionally vote, leave with action items — anyone with the link can join."
  end

  defp chamber_og_description(%{activity: "minigame"} = chamber) do
    "Join the mini-game in #{chamber.title}. Draw and guess, race the clock, climb the scoreboard — anyone with the link can join."
  end

  defp chamber_og_description(chamber) do
    "Join the live jam in #{chamber.title}. Pick an instrument, hear everyone else who has the link."
  end

  defp instrument_label(:drums), do: "Drums"
  defp instrument_label(:keyboard), do: "Keyboard"
  defp instrument_label(:guitar), do: "Guitar"
  defp instrument_label(:bass), do: "Bass"
  defp instrument_label(:pad), do: "Pad"
  defp instrument_label(:suling), do: "Suling"
  defp instrument_label(:kendang), do: "Kendang"

  # Activity-specific presence copy. "Jamming" carries music
  # connotation; "Here" is neutral for non-music activities.
  defp presence_heading("music"), do: "Jamming"
  defp presence_heading(_), do: "Here"

  defp presence_label("music"), do: "jamming"
  defp presence_label(_), do: "here"

  # Color of the small dot next to each user in the presence panel.
  # Music uses the per-instrument neon; everything else falls back
  # to the muted-foreground token so the dot doesn't reference a
  # meaningless instrument choice.
  defp presence_dot_color("music", meta), do: accent_var(meta.instrument)
  defp presence_dot_color(_, _), do: "var(--muted-foreground)"

  # Deterministic geometric identicon (GitHub-style, left-right
  # symmetric 5x5 grid) for a player, seeded by user_id. Permanent per
  # user — same id always yields the same pattern + color. The Vue
  # side (assets/vue/lib/identicon.ts) mirrors this exact algorithm so
  # a player looks identical in the presence panel and the mini-game
  # scoreboard. FNV-1a/32 over the id's bytes; UUIDs are ASCII so the
  # Elixir (bytes) and JS (char codes) hashes agree.
  attr :seed, :string, required: true
  attr :class, :string, default: "size-5"

  def player_identicon(assigns) do
    {hue, cells} = identicon_data(assigns.seed)
    assigns = assign(assigns, hue: hue, cells: cells)

    ~H"""
    <svg viewBox="0 0 5 5" class={["rounded shrink-0", @class]} aria-hidden="true">
      <rect width="5" height="5" fill={"oklch(0.93 0.03 #{@hue})"} />
      <rect
        :for={{x, y} <- @cells}
        x={x}
        y={y}
        width="1.02"
        height="1.02"
        fill={"oklch(0.58 0.19 #{@hue})"}
      />
    </svg>
    """
  end

  defp identicon_data(seed) do
    h = fnv1a(seed)
    hue = rem(h, 360)

    cells =
      for y <- 0..4, x <- 0..2, bit_set?(h, y * 3 + x), reduce: [] do
        acc ->
          mirrored = if x < 2, do: [{4 - x, y}], else: []
          [{x, y} | mirrored] ++ acc
      end

    {hue, cells}
  end

  defp bit_set?(h, i), do: band(bsr(h, i), 1) == 1

  defp fnv1a(seed) do
    seed
    |> :binary.bin_to_list()
    |> Enum.reduce(2_166_136_261, fn byte, acc ->
      band(bxor(acc, byte) * 16_777_619, 0xFFFFFFFF)
    end)
  end

  # Trim the presence map down to the subset PokerBoard / the
  # mini-game lobby need: user_id + display_name + alias, sorted
  # by joined_at so the row order is stable across renders.
  @doc false
  def participants(presences) do
    presences
    |> Enum.map(fn {user_id, %{metas: [meta | _]}} ->
      %{
        user_id: user_id,
        display_name: meta.display_name,
        alias: meta.alias,
        joined_at: meta.joined_at
      }
    end)
    |> Enum.sort_by(& &1.joined_at)
    |> Enum.map(&Map.delete(&1, :joined_at))
  end

  # Static class strings per instrument so Tailwind picks them up at
  # build time. Uses the per-instrument neon variables defined in
  # app.css. Tailwind can't synthesize these from a runtime string.
  defp active_tab_class(:drums), do: "bg-accent-drums/15 text-accent-drums"
  defp active_tab_class(:keyboard), do: "bg-accent-keyboard/15 text-accent-keyboard"
  defp active_tab_class(:guitar), do: "bg-accent-guitar/15 text-accent-guitar"
  defp active_tab_class(:bass), do: "bg-accent-bass/15 text-accent-bass"
  defp active_tab_class(:pad), do: "bg-accent-pad/15 text-accent-pad"
  defp active_tab_class(:suling), do: "bg-accent-suling/15 text-accent-suling"
  defp active_tab_class(:kendang), do: "bg-accent-kendang/15 text-accent-kendang"

  defp accent_var(:drums), do: "var(--accent-drums)"
  defp accent_var(:keyboard), do: "var(--accent-keyboard)"
  defp accent_var(:guitar), do: "var(--accent-guitar)"
  defp accent_var(:bass), do: "var(--accent-bass)"
  defp accent_var(:pad), do: "var(--accent-pad)"
  defp accent_var(:suling), do: "var(--accent-suling)"
  defp accent_var(:kendang), do: "var(--accent-kendang)"

  # Full URL the creator can copy + paste anywhere. Built from the
  # endpoint's configured host so the link works regardless of
  # whether the user is on localhost, a staging URL, or prod.
  defp chamber_url(chamber) do
    MixchambWeb.Endpoint.url() <> "/chamber/" <> chamber.slug
  end

  # Whether to show the "Share this chamber" disclosure. Anyone
  # in the chamber sees it; the chaos chamber (system row with
  # no human creator + a known slug) is the only exception —
  # its URL is public knowledge, no point cluttering the chrome.
  # Previously creator-only + grace-window-only; loosened
  # because hosts wanted to share the URL after the chamber
  # was already activated, and non-creators sometimes want to
  # forward the link too.
  defp show_invite_banner?(chamber, _current_user) do
    not is_nil(chamber.creator_user_id)
  end

  defp creator?(chamber, current_user), do: chamber.creator_user_id == current_user.id

  # Order matters — drives chip render order. From driest to wettest
  # so the picker reads as a "spectrum" left-to-right.
  @chamber_kinds ~w(vacuum anechoic room live hall cathedral plate spring echo)
  defp chamber_kinds, do: @chamber_kinds

  defp chamber_kind_label("vacuum"), do: "Vacuum"
  defp chamber_kind_label("anechoic"), do: "Anechoic"
  defp chamber_kind_label("room"), do: "Room"
  defp chamber_kind_label("live"), do: "Live"
  defp chamber_kind_label("hall"), do: "Hall"
  defp chamber_kind_label("cathedral"), do: "Cathedral"
  defp chamber_kind_label("plate"), do: "Plate"
  defp chamber_kind_label("spring"), do: "Spring"
  defp chamber_kind_label("echo"), do: "Echo"

  defp chamber_kind_blurb("vacuum"), do: "Raw signal, no FX"
  defp chamber_kind_blurb("anechoic"), do: "No room, instrument FX kept"
  defp chamber_kind_blurb("room"), do: "Small, present"
  defp chamber_kind_blurb("live"), do: "Warm, lush"
  defp chamber_kind_blurb("hall"), do: "Big, sustained"
  defp chamber_kind_blurb("cathedral"), do: "Vast, ethereal"
  defp chamber_kind_blurb("plate"), do: "Bright, vintage"
  defp chamber_kind_blurb("spring"), do: "Boingy, lo-fi"
  defp chamber_kind_blurb("echo"), do: "Discrete repeats"

  # Display title or fallback. Used both in the page <title> and
  # the heading above the stage.
  # Pre-rename chambers don't have a title yet. The slug lives in
  # the URL bar — no need to leak it into the H1. "Untitled chamber"
  # alone is the friendlier placeholder; the creator's inline-edit
  # form sits right below the H1 so they can rename in one tap.
  defp display_title(%{title: nil}), do: "Untitled chamber"
  defp display_title(%{title: title}), do: title

  defp page_title_for(chamber), do: "#{display_title(chamber)} · mixchamb"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      banner={assigns[:banner]}
      draining?={assigns[:draining?] || false}
      width={:wide}
    >
      <%!-- Break out of Layouts.app's max-w-3xl + py-10. The chamber
           uses the full available width as a stage; the dock floats
           at the bottom of the viewport. --%>
      <%!-- Bottom padding clears the floating dock + the iOS
           home-indicator gesture area. `env(safe-area-inset-bottom)`
           is 0 on devices without a notch / home bar. --%>
      <div class="-mx-4 sm:-mx-6 lg:-mx-8 -my-10 px-4 sm:px-6 lg:px-8 pt-4 pb-[calc(7rem+env(safe-area-inset-bottom))]">
        <%!-- Chamber stage centered in max-w-5xl. The presence
             aside is detached entirely — it floats over the
             chamber as a draggable panel (see the <aside> after
             this block). Layouts.app gets `width={:wide}` so the
             5xl actually applies; without the override the parent
             clamps the chamber to max-w-3xl. --%>
        <div class="mx-auto max-w-5xl">
          <div class="space-y-4">
            <%!-- Leave-chamber back link. Small + subtle so it
               doesn't compete with the controls; navigates back
               to the landing page. --%>
            <div>
              <.link
                navigate={~p"/"}
                class="inline-flex items-center gap-1 text-xs text-muted-foreground hover:text-foreground transition-colors"
              >
                <.icon name="hero-arrow-left-mini" class="size-3.5" /> Leave chamber
              </.link>
            </div>

            <%!-- Title heading. The creator gets an inline form that
               renames the chamber on submit (Enter / blur); other
               users see a static heading. The fallback when no
               title is set shows the slug so the placeholder still
               feels chamber-specific. --%>
            <div>
              <%= if creator?(@chamber, @current_user) do %>
                <form phx-submit="save_title" class="flex items-baseline gap-2">
                  <input
                    type="text"
                    name="title"
                    value={@chamber.title || ""}
                    maxlength="80"
                    placeholder="Untitled chamber"
                    class="flex-1 bg-transparent border-none outline-none text-2xl font-bold tracking-tight font-display text-foreground placeholder:text-muted-foreground/80"
                  />
                  <%!-- The hint is just clutter on mobile, where on-screen
                     keyboards already show their own submit affordance. --%>
                  <span class="hidden sm:inline text-[10px] uppercase tracking-wider text-muted-foreground/60">
                    Press enter to save
                  </span>
                </form>
              <% else %>
                <h1 class="text-2xl font-bold tracking-tight font-display">
                  {display_title(@chamber)}
                </h1>
              <% end %>
            </div>

            <%!-- Activity switcher. Host-only chip-strip to flip
               between music and poker mid-session. Hidden on the
               singleton chaos chamber (it's music-locked by design;
               its creator_user_id is NULL so @is_host is already
               false). The server cast clears the PokerSession on
               music and allocates a fresh one on poker, then
               broadcasts :activity_changed for every connected
               client. --%>
            <div :if={@is_host} class="flex flex-wrap items-center gap-2">
              <span class="text-xs uppercase tracking-wider text-muted-foreground mr-1">
                Activity
              </span>
              <button
                :for={a <- Mixchamb.Chambers.Chamber.activities()}
                phx-click="set_activity"
                phx-value-activity={a}
                data-confirm={
                  if a != @chamber.activity and a == "music" and @poker_session != nil and
                       map_size(@poker_session.votes) > 0,
                     do: "Switching to music will drop the current poker votes. Continue?"
                }
                class={[
                  "px-3 py-1 text-xs rounded-md border transition-colors cursor-pointer",
                  @chamber.activity == a && activity_chip_active_class(a),
                  @chamber.activity != a &&
                    "bg-card hover:bg-accent text-foreground border-border"
                ]}
              >
                {activity_label(a)}
              </button>
            </div>

            <%!-- Chamber kind. Creator gets a chip-strip to switch
               between presets; everyone else sees a single chip
               showing what's active. Changes ripple via the
               :chamber_updated broadcast so the FX bus on every
               client retunes within ~100 ms. Music-only — kind is
               the audio reverb preset and is meaningless outside
               music chambers. --%>
            <div
              :if={@chamber.activity == "music"}
              class="flex flex-wrap items-center gap-2"
            >
              <span class="text-xs uppercase tracking-wider text-muted-foreground mr-1">
                Kind
              </span>
              <%= if Music.can_change_kind?(@chamber, @current_user, @current_admin) do %>
                <button
                  :for={kind <- chamber_kinds()}
                  phx-click="set_kind"
                  phx-value-kind={kind}
                  title={chamber_kind_blurb(kind)}
                  class={[
                    "px-3 py-1 text-xs rounded-md border transition-colors cursor-pointer",
                    @chamber.kind == kind &&
                      "bg-primary/15 text-primary border-primary/40",
                    @chamber.kind != kind &&
                      "bg-card hover:bg-accent text-foreground border-border"
                  ]}
                >
                  {chamber_kind_label(kind)}
                </button>
              <% else %>
                <span
                  class="inline-flex items-center gap-1 px-3 py-1 text-xs rounded-md border bg-card text-foreground"
                  title={chamber_kind_blurb(@chamber.kind)}
                >
                  {chamber_kind_label(@chamber.kind)}
                  <span class="text-muted-foreground">
                    · {chamber_kind_blurb(@chamber.kind)}
                  </span>
                </span>
              <% end %>
            </div>

            <%!-- Recording controls. Creator gets a REC toggle.
               Everyone sees the live REC badge while recording is
               on, and a "Play recording" button once there's at
               least one persisted event. Music-only — only audio
               events are captured / replayed. --%>
            <div
              :if={@chamber.activity == "music"}
              class="flex flex-wrap items-center gap-2"
            >
              <span class="text-xs uppercase tracking-wider text-muted-foreground mr-1">
                Recording
              </span>

              <button
                :if={creator?(@chamber, @current_user)}
                phx-click="toggle_recording"
                data-confirm={
                  if not @chamber.is_recording and @has_pending_audio,
                    do:
                      "Starting a new recording will replace the current audio file (it hasn't been downloaded). Continue?"
                }
                type="button"
                aria-pressed={to_string(@chamber.is_recording)}
                aria-label={
                  if @chamber.is_recording,
                    do: "Stop recording",
                    else: "Start recording"
                }
                class={[
                  "inline-flex items-center gap-1.5 px-3 py-1 text-xs rounded-md border transition-colors cursor-pointer",
                  @chamber.is_recording &&
                    "bg-red-500/15 text-red-500 border-red-500/40 hover:bg-red-500/20",
                  !@chamber.is_recording &&
                    "bg-card hover:bg-accent text-foreground border-border"
                ]}
                title={
                  if @chamber.is_recording,
                    do: "Click to stop recording",
                    else: "Click to start recording"
                }
              >
                <span
                  aria-hidden="true"
                  class={[
                    "size-2 rounded-full",
                    @chamber.is_recording && "bg-red-500 animate-pulse",
                    !@chamber.is_recording && "bg-muted-foreground/40"
                  ]}
                ></span>
                {if @chamber.is_recording, do: "REC · click to stop", else: "Start recording"}
              </button>

              <%!-- Screen-reader-only live region. The button label
                 already changes between "Start recording" /
                 "Stop recording" on toggle, but a polite live
                 region also announces the state transition itself
                 so AT users hear "Recording started" without
                 needing to re-focus the button. --%>
              <div role="status" aria-live="polite" aria-atomic="true" class="sr-only">
                {if @chamber.is_recording, do: "Recording started", else: "Recording stopped"}
              </div>

              <%!-- Non-creator live badge — visible only while
                 recording is on. Mirrors the creator's button
                 style minus the click affordance. --%>
              <span
                :if={!creator?(@chamber, @current_user) and @chamber.is_recording}
                class="inline-flex items-center gap-1.5 px-3 py-1 text-xs rounded-md border bg-red-500/15 text-red-500 border-red-500/40"
              >
                <span class="size-2 rounded-full bg-red-500 animate-pulse"></span> REC
              </span>

              <%!-- Play recording — anyone. Shown only when there's
                 something to replay and recording is currently off
                 (so we don't double-stack a live jam with a replay
                 of the same jam). Icon-only chip so it doesn't
                 compete with the REC text button next to it; full
                 label lives in the title for hover + AT users. --%>
              <button
                :if={@recorded_count > 0 and not @chamber.is_recording}
                phx-click="play_recording"
                type="button"
                aria-label={"Play recording (#{@recorded_count} notes)"}
                class="inline-flex items-center gap-1.5 px-2 py-1 text-xs rounded-md border bg-card hover:bg-accent text-foreground border-border cursor-pointer transition-colors"
                title={"Replay all #{@recorded_count} recorded notes"}
              >
                <.icon name="hero-play-mini" class="size-3.5" />
                <span class="text-muted-foreground tabular-nums">{@recorded_count}</span>
              </button>

              <%!-- Reset recording — creator-only. Wipes the persisted
                 events for this chamber and tells the client to
                 drop its captured audio blob. Disabled while
                 recording is on (would race with the GenServer's
                 batched flush). Icon-only for the same reason as
                 Play — keeps the REC toggle the visible primary. --%>
              <button
                :if={
                  creator?(@chamber, @current_user) and @recorded_count > 0 and
                    not @chamber.is_recording
                }
                phx-click="reset_recording"
                data-confirm="Delete the saved recording for this chamber? This can't be undone."
                type="button"
                aria-label="Reset recording"
                class="inline-flex items-center justify-center size-7 rounded-md border bg-card hover:bg-destructive/10 hover:text-destructive hover:border-destructive/40 text-muted-foreground border-border cursor-pointer transition-colors"
                title="Delete this chamber's recorded events"
              >
                <.icon name="hero-trash-mini" class="size-3.5" />
              </button>
            </div>

            <%!-- One-click "Copy share link" button — visible to
               anyone in the chamber (host inviting new
               participants, participants forwarding the link).
               Hidden only on the system Chaos chamber, where
               the URL is public knowledge.

               The CopyToClipboard hook in assets/js/app.js
               handles the click → copy → "Copied!" flash →
               restore-original-text cycle, so no Vue / LV
               round-trip needed. --%>
            <div
              :if={show_invite_banner?(@chamber, @current_user)}
              class="flex items-center justify-end"
            >
              <button
                type="button"
                id="chamber-copy-link"
                phx-hook="CopyToClipboard"
                phx-update="ignore"
                data-copy-url={chamber_url(@chamber)}
                class="inline-flex items-center gap-1.5 rounded-md border bg-card hover:bg-accent px-3 py-1.5 text-xs font-medium transition-colors cursor-pointer"
                title="Copy this chamber's URL to clipboard"
              >
                <.icon name="hero-link-mini" class="size-4" />
                <span>Copy share link</span>
              </button>
            </div>

            <%!-- One live_vue island for the whole chamber. Vue handles
               the v-if swap between pads internally — see Chamber.vue
               for why we don't use three separate islands. --%>
            <.Chamber
              current_instrument={Atom.to_string(@current_instrument)}
              chamber_kind={@chamber.kind}
              chamber_title={@chamber.title}
              chamber_slug={@chamber.slug}
              activity={@chamber.activity}
              presence_count={map_size(@presences)}
              poker_session={Poker.view(@poker_session, @current_user.id)}
              poker_participants={participants(@presences)}
              retro_session={Retro.view(@retro_session)}
              retro_tallies={@retro_tallies}
              retro_my_votes={MapSet.to_list(@retro_my_votes)}
              retro_discussing_card_id={@retro_discussing_card_id}
              retro_timer_deadline={@retro_timer_deadline}
              retro_participant_aliases={Retro.participant_aliases(@presences)}
              retro_last_archived={Retro.last_archived(@past_retros)}
              retro_previous_actions={Retro.previous_actions_view(@retro_previous_actions)}
              minigame_state={MiniGame.view(@minigame_state, @current_user.id)}
              minigame_participants={participants(@presences)}
              current_user_id={@current_user.id}
              current_user_alias={@current_user.alias || @current_user.display_name}
              is_host={@is_host}
            />
          </div>

          <%!-- Floating, user-positionable presence panel. Starts at
           top-right (lg:fixed + lg:top-24 + lg:right-4) but the
           `phx-hook="DraggablePanel"` lets the user grab the header
           row and drag it anywhere; position is persisted to
           localStorage so the chosen spot survives reloads.
           Hidden below lg because the chamber pads need the
           horizontal room on tablet / mobile; the dock's presence
           summary at the bottom is the fallback there. --%>
          <aside
            id="chamber-presence-panel"
            phx-hook="DraggablePanel"
            data-storage-key="mixchamb:chamber-presence-panel"
            class="hidden lg:block lg:fixed lg:top-24 lg:right-4 w-56 z-30"
          >
            <div class="rounded-xl border bg-card/80 backdrop-blur-md shadow-lg">
              <div
                data-drag-handle
                class="flex items-center justify-between px-3 py-2 border-b cursor-grab select-none touch-none [&.is-dragging]:cursor-grabbing"
                title="Drag to reposition"
              >
                <span class="text-xs font-semibold uppercase tracking-wider font-display">
                  {presence_heading(@chamber.activity)}
                </span>
                <span class="text-xs text-muted-foreground tabular-nums">
                  {map_size(@presences)}
                </span>
              </div>
              <.presence_panel_body
                id_prefix="desktop"
                current_user={@current_user}
                chamber={@chamber}
                presences={@presences}
                hosts={@hosts}
                recent_hits={@recent_hits}
                past_retros={@past_retros}
              />
            </div>
          </aside>

          <%!-- Mobile presence sheet. Mirrors the desktop aside's
           content (alias editor + user list with host management)
           on a screen the aside can't reach. Triggered by tapping
           the dock's presence pill; `lg:hidden` keeps it out of the
           way on desktops where the aside is already visible.
           Recent-hits feed is suppressed in the sheet — host
           management is the priority on mobile, and the feed has
           plenty of room on desktop. --%>
          <div
            :if={@presence_sheet_open}
            class="lg:hidden fixed inset-0 z-50 flex flex-col p-4 pt-16"
            role="dialog"
            aria-label="Players panel"
          >
            <button
              type="button"
              phx-click="toggle_presence_sheet"
              aria-label="Close players panel"
              class="absolute inset-0 -z-10 backdrop-blur-md bg-background/80 cursor-pointer"
            ></button>
            <div class="relative mx-auto w-full max-w-md rounded-xl border bg-card shadow-2xl flex flex-col overflow-hidden">
              <div class="flex items-center justify-between px-3 py-2 border-b shrink-0">
                <span class="text-xs font-semibold uppercase tracking-wider font-display">
                  {presence_heading(@chamber.activity)}
                  <span class="ml-1 text-muted-foreground tabular-nums">
                    {map_size(@presences)}
                  </span>
                </span>
                <button
                  type="button"
                  phx-click="toggle_presence_sheet"
                  class="text-muted-foreground hover:text-foreground cursor-pointer text-lg leading-none px-2 py-1 -mr-1"
                  aria-label="Close"
                >
                  ×
                </button>
              </div>
              <div class="flex-1 overflow-y-auto">
                <.presence_panel_body
                  id_prefix="mobile"
                  current_user={@current_user}
                  chamber={@chamber}
                  presences={@presences}
                  hosts={@hosts}
                  past_retros={@past_retros}
                />
              </div>
            </div>
          </div>
        </div>
      </div>

      <%!-- Floating dock: instrument switcher + presence summary.
           Fixed at the viewport's bottom edge so it stays in reach
           regardless of page scroll. `pointer-events-none` on the
           outer wrapper lets clicks pass through the empty area
           around the dock to whatever is behind it. --%>
      <%!-- Dock floats just above the bottom edge — `max(...)` keeps
           it 1rem off the bottom on a flat-bottomed device and
           lifts it above the iOS home-indicator on a notched one. --%>
      <div class="fixed inset-x-0 bottom-[max(1rem,env(safe-area-inset-bottom))] px-4 z-40 pointer-events-none">
        <div class="mx-auto max-w-3xl pointer-events-auto">
          <%!-- Latency disclaimer. Real musical timing needs sub-30 ms;
               WebSocket fan-out can't promise that, so we tell the
               user up front instead of pretending. Hidden on mobile
               where the dock already eats most of the bottom strip.
               Music-only — poker votes don't care about timing. --%>
          <p
            :if={@chamber.activity == "music"}
            class="hidden sm:block text-center text-[10px] uppercase tracking-wider text-muted-foreground/70 mb-1.5"
          >
            Best-effort sync · distant players may sound a beat off
          </p>
          <div class="flex items-center gap-2 rounded-xl border bg-card/80 backdrop-blur-md px-2 py-1.5 shadow-2xl">
            <%!-- Instrument switcher tabs. Music-only — non-music
                 activities don't pick an instrument. --%>
            <div
              :if={@chamber.activity == "music"}
              class="flex items-center gap-1 flex-1 overflow-x-auto"
            >
              <button
                :for={inst <- @instruments}
                phx-click="switch_instrument"
                phx-value-to={inst}
                aria-label={instrument_label(inst)}
                aria-pressed={to_string(@current_instrument == inst)}
                class={[
                  "pad-touch touch-manipulation min-h-11 min-w-11 px-3 py-1.5 text-sm rounded-lg transition-all flex items-center justify-center gap-1.5 whitespace-nowrap cursor-pointer",
                  @current_instrument == inst && active_tab_class(inst),
                  @current_instrument != inst &&
                    "text-muted-foreground hover:bg-accent hover:text-foreground"
                ]}
                title={instrument_label(inst)}
              >
                <span
                  aria-hidden="true"
                  class="size-2 rounded-full opacity-80"
                  style={"background-color: " <> accent_var(inst)}
                ></span>
                <%!-- On mobile, only the active tab keeps its
                     label; the rest collapse to a dot so all 7
                     fit without horizontal scroll. --%>
                <span class={[@current_instrument != inst && "hidden sm:inline"]}>
                  {instrument_label(inst)}
                </span>
              </button>
            </div>

            <%!-- Divider between instrument switcher + presence
                 summary. Only needed when the switcher is visible. --%>
            <div
              :if={@chamber.activity == "music"}
              class="w-px h-6 bg-border shrink-0"
            >
            </div>

            <%!-- Presence summary: avatar stack + count. Becomes
                 a button on mobile to surface the host-management
                 sheet (the floating aside is `hidden lg:block`,
                 so without this affordance there's no way to
                 promote / demote / step down from a phone).
                 On lg+ the click still flips `presence_sheet_open`
                 but the sheet itself is `lg:hidden`, so no visible
                 effect — desktop already has the aside open. --%>
            <button
              type="button"
              phx-click="toggle_presence_sheet"
              aria-label="Show players panel"
              class="flex items-center gap-2 pr-2 pl-1 shrink-0 rounded-md transition-colors lg:hover:bg-transparent hover:bg-accent/40 lg:cursor-default cursor-pointer"
            >
              <div class="flex -space-x-1.5">
                <span
                  :for={{user_id, %{metas: [meta | _]}} <- Enum.take(@presences, 4)}
                  class={[
                    "size-7 rounded-full flex items-center justify-center text-[10px] font-semibold border-2 border-card",
                    user_id == @current_user.id && "bg-primary text-primary-foreground",
                    user_id != @current_user.id && "bg-muted text-muted-foreground"
                  ]}
                  aria-label={"#{primary_name(meta)}#{if alias_set?(meta), do: " · " <> meta.display_name, else: ""} on #{instrument_label(meta.instrument)}"}
                  title={"#{primary_name(meta)}#{if alias_set?(meta), do: " · " <> meta.display_name, else: ""} · #{instrument_label(meta.instrument)}"}
                >
                  {primary_name(meta) |> String.first() |> String.upcase()}
                </span>
              </div>
              <%!-- Just the count on mobile, full label on sm+
                   where the dock has room for both. Label tracks
                   activity: "jamming" for music, "here" otherwise. --%>
              <span class="text-xs text-muted-foreground tabular-nums whitespace-nowrap">
                {map_size(@presences)}<span class="hidden sm:inline">{" " <>
                  presence_label(@chamber.activity)}</span>
              </span>
            </button>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  # Inner body of the presence panel — alias editor, user list with
  # badges + promote/demote controls, recent-hits feed (music only).
  # Shared between the desktop floating aside and the mobile sheet
  # so host management stays at parity across viewports. Caller
  # passes a unique `id_prefix` for the alias editor's form id;
  # without it both surfaces would mount a `#alias-editor` and
  # collide. `recent_hits` defaults to `[]` so a caller can suppress
  # the feed (the mobile sheet does, to keep the sheet focused on
  # host management — the feed lives on desktop where there's room).
  attr :id_prefix, :string, required: true
  attr :current_user, :map, required: true
  attr :chamber, :map, required: true
  attr :presences, :map, required: true
  attr :hosts, :any, required: true
  attr :recent_hits, :list, default: []
  attr :past_retros, :list, default: []

  defp presence_panel_body(assigns) do
    ~H"""
    <%!-- Inline alias editor for the current user. Submits on
         Enter or blur; empty input clears the alias. Sits at
         the top so "your identity" is the first thing in the
         panel; the user list below shows everyone else
         relative to that. --%>
    <form
      phx-submit="set_alias"
      phx-change="set_alias"
      class="border-b p-2"
      id={@id_prefix <> "-alias-editor"}
      phx-update="ignore"
    >
      <label class="block text-[10px] uppercase tracking-wider text-muted-foreground mb-1 px-1">
        Your alias
      </label>
      <input
        type="text"
        name="alias"
        value={@current_user.alias || ""}
        maxlength="32"
        placeholder="Set a nickname…"
        phx-debounce="600"
        class="w-full bg-transparent border border-input rounded-md px-2 py-1 text-xs outline-none focus:border-primary/60"
      />
      <p class="text-[10px] text-muted-foreground mt-1 px-1">
        Shown above {@current_user.display_name}. Empty to clear.
      </p>
    </form>
    <ul class="max-h-[60vh] overflow-y-auto py-1">
      <li
        :for={{user_id, %{metas: [meta | _]}} <- @presences}
        class={[
          "flex items-start gap-2 px-3 py-1.5 text-sm",
          user_id == @current_user.id && "bg-primary/5"
        ]}
      >
        <%!-- Instrument dot — music only (the colour encodes the
             player's instrument). Hidden for non-music activities. --%>
        <span
          :if={@chamber.activity == "music"}
          aria-hidden="true"
          class="size-2 rounded-full shrink-0 mt-2"
          style={"background-color: " <> presence_dot_color(@chamber.activity, meta)}
        ></span>
        <%!-- Geometric identicon with a permanent per-user colour —
             the player's stable visual identity across activities. --%>
        <.player_identicon seed={user_id} class="size-5 mt-0.5" />
        <div class="flex-1 min-w-0">
          <%!-- Primary line: the alias if set, else the
               auto-generated noun-adj-NN name. Host badge sits
               inline so the role is visible at the same glance
               as the name. --%>
          <div class={[
            "flex items-baseline gap-1.5 leading-tight",
            user_id == @current_user.id && "font-semibold text-foreground",
            user_id != @current_user.id && "text-foreground"
          ]}>
            <span class="truncate min-w-0">{primary_name(meta)}</span>
            <span :if={user_id == @current_user.id} class="text-muted-foreground font-normal shrink-0">
              (you)
            </span>
            <span
              :if={user_id == @chamber.creator_user_id}
              class="shrink-0 text-[9px] uppercase tracking-wider font-mono font-semibold px-1 rounded bg-primary/15 text-primary"
            >
              Creator
            </span>
            <span
              :if={user_id != @chamber.creator_user_id and MapSet.member?(@hosts, user_id)}
              class="shrink-0 text-[9px] uppercase tracking-wider font-mono font-semibold px-1 rounded bg-accent-poker/15 text-accent-poker"
            >
              Host
            </span>
          </div>
          <%!-- Secondary line: the anon name whenever an alias
               is present (so the auto-generated identifier never
               disappears), with the instrument label trailing. --%>
          <div
            :if={@chamber.activity == "music" or alias_set?(meta)}
            class="text-[11px] text-muted-foreground leading-tight truncate font-mono"
          >
            <span :if={alias_set?(meta)}>{meta.display_name}</span><span :if={
              alias_set?(meta) and @chamber.activity == "music"
            }> · </span><span :if={@chamber.activity == "music"}>{instrument_label(meta.instrument)}</span>
          </div>
          <%!-- Host management. Creator viewing someone else
               gets Promote / Demote; a co-host viewing themselves
               gets Step down; everyone else sees nothing. --%>
          <div
            :if={creator?(@chamber, @current_user) and user_id != @chamber.creator_user_id}
            class="mt-1"
          >
            <button
              :if={MapSet.member?(@hosts, user_id)}
              type="button"
              phx-click="demote_host"
              phx-value-user_id={user_id}
              class="text-[10px] text-muted-foreground hover:text-foreground underline-offset-2 hover:underline cursor-pointer"
            >
              Demote
            </button>
            <button
              :if={not MapSet.member?(@hosts, user_id)}
              type="button"
              phx-click="promote_host"
              phx-value-user_id={user_id}
              class="text-[10px] text-muted-foreground hover:text-foreground underline-offset-2 hover:underline cursor-pointer"
              title="Make this player a co-host. They can reveal / advance / set queue / switch activity."
            >
              Promote to host
            </button>
          </div>
          <div
            :if={
              user_id == @current_user.id and
                MapSet.member?(@hosts, user_id) and
                user_id != @chamber.creator_user_id
            }
            class="mt-1"
          >
            <button
              type="button"
              phx-click="demote_host"
              phx-value-user_id={user_id}
              class="text-[10px] text-muted-foreground hover:text-foreground underline-offset-2 hover:underline cursor-pointer"
            >
              Step down as host
            </button>
          </div>
        </div>
      </li>
    </ul>
    <%!-- Recent-hits feed (music-only). Caller passes [] to
         suppress (the mobile sheet does — keeps it focused on
         host management; the desktop aside has the room). --%>
    <div
      :if={@chamber.activity == "music" and @recent_hits != []}
      class="border-t px-2 py-1.5 space-y-0.5"
      aria-live="polite"
      aria-label="Recent plays"
    >
      <div
        :for={hit <- @recent_hits}
        id={"hit-#{@id_prefix}-#{hit.ref}"}
        class="recent-hit flex items-center gap-1.5 text-[11px] leading-tight px-1 py-0.5 rounded font-mono"
      >
        <span
          aria-hidden="true"
          class="size-1.5 rounded-full shrink-0"
          style={"background-color: " <> accent_var(hit.instrument)}
        ></span>
        <span class={[
          "truncate min-w-0",
          hit.is_self && "text-foreground font-semibold",
          !hit.is_self && "text-muted-foreground"
        ]}>
          {hit.user_name}
        </span>
        <span class="text-muted-foreground shrink-0">·</span>
        <span class="truncate min-w-0 text-foreground">{hit.label}</span>
      </div>
    </div>

    <%!-- Past retros disclosure — retro chambers only, hidden
         when there's no history yet. Shows session title (or
         "Untitled retro") + archived date; each entry links to
         its read-only permalink at /archives/retros/:id.
         Caller passes [] for non-retro chambers (default). --%>
    <details
      :if={@chamber.activity == "retro" and @past_retros != []}
      class="border-t group"
    >
      <summary class="cursor-pointer px-3 py-2 text-[10px] uppercase tracking-wider text-muted-foreground font-display flex items-center justify-between hover:text-foreground">
        <span>Past retros ({length(@past_retros)})</span>
        <span class="text-[10px] group-open:rotate-90 transition-transform" aria-hidden="true">
          ›
        </span>
      </summary>
      <ul class="px-2 pb-2 space-y-1">
        <li
          :for={past <- @past_retros}
          class="text-[11px] leading-tight"
        >
          <.link
            navigate={~p"/archives/retros/#{past.id}"}
            class="block rounded-md border bg-background/40 hover:bg-accent transition-colors px-2 py-1.5"
          >
            <div class="font-medium truncate text-foreground">
              {past.title || "Untitled retro"}
            </div>
            <div class="text-muted-foreground tabular-nums text-[10px]">
              archived {Calendar.strftime(past.archived_at, "%Y-%m-%d %H:%M") <> " UTC"}
            </div>
          </.link>
        </li>
      </ul>
    </details>
    """
  end
end
