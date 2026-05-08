# mixwave

A real-time collaborative studio. **One global jam room** — anyone
who hits the URL joins a single shared session, picks an instrument
(drums, keyboard, guitar), picks a flavor for that instrument, and
plays alongside everyone else online. No accounts, no separate rooms.

The project's framing is *"my tech learning journey"*: Vue and
Elixir/Phoenix/LiveView are the two stacks I picked up over the last
year, and mixwave is the project where they finally meet. See
[BRAINSTORM.md](./BRAINSTORM.md) for the audience, talk shape, and
per-layer flagship features.

## What it does (v1)

- **Anonymous identity, no signup.** First visit gets you a
  Javanese-flavored handle (`ayu-merak-42`, `wani-macan-17`). Idle
  users (24 h+) are reaped by a supervised GenServer.
- **Three instruments, three flavors each — nine engines total:**

  | Instrument | Flavors |
  | --- | --- |
  | **Drums** (5 pads — kick / snare / hi-hat / open hat / crash) | Synth · 808 · Acoustic |
  | **Keyboard** (one octave C4–C5) | Synth · Lead · **Piano** *(sampled)* |
  | **Guitar** (8 chord buttons) | Synth · **Pluck** *(hand-rolled Karplus-Strong)* · **Acoustic** *(sampled)* |

  Seven flavors are pure DSP (Tone.js synths). Two are sampled —
  Salamander piano and acoustic guitar — streamed lazily from a
  CDN the first time someone picks them.

- **Tap pads or use keyboard shortcuts.** Drums on `1–5`, keyboard
  on the QWERTY row (`a w s e d f t g y h u j k`), guitar chords
  on `1–8`.
- **Everyone hears everyone.** Notes broadcast via Phoenix.PubSub
  on a single global topic; an always-mounted Vue island
  (`JamReceiver`/`Studio.vue`) plays them locally on every other
  connected user. Listeners hear the *sender's* chosen flavor —
  coherent jam sound for the whole room.
- **Presence sidebar** shows who's in the room and what each
  player has on screen, updates live on join/leave/switch.
- **1-second cooldown** on instrument switch. Held notes cut off
  on switch (no bleed across instruments or flavors).
- **Latency hint** in the footer: *"best-effort sync — distant
  users may sound a beat off."* WebSocket delay between players is
  ~50–150 ms; this is an honest jam-along, not a synchronized
  performance.

### What's planned

- **v2:** save the last 30 seconds of jam → playback widget;
  supervisor LiveView with a chaos button that kills
  `Studio.Room` and watches the supervisor restart it; per-user
  volume; more instruments.
- **v3:** Fly.io multi-node deploy with `dns_cluster` auto-clustering;
  cluster LiveView showing nodes / process counts / drain-node
  button (cross-node Presence rebalancing live); public release.

## Stack

| Layer | What |
| --- | --- |
| Backend | Elixir 1.18+, **Phoenix 1.8** + **LiveView 1.1**, Ecto + Postgres, Bandit, `dns_cluster` |
| Realtime | **Phoenix.PubSub** for note broadcasts, **Phoenix.Presence** for the sidebar |
| Frontend | **Vue 3.5** + TypeScript (strict), Vite 8, Tailwind v4, **shadcn-vue** (Reka UI primitives), Lucide icons |
| LV ↔ Vue | **`live_vue` 1.2** — Vue islands rendered inside LiveView |
| Audio | **Tone.js** — 7 synth-based engines + 2 `Tone.Sampler` engines streaming from `tonejs.github.io/audio` and `nbrosowsky.github.io/tonejs-instruments` |
| Hosting (planned) | Fly.io |

The HEEX side and the Vue island side share one design language —
shadcn-vue's CSS variables (`bg-background`, `text-foreground`,
`bg-primary`, etc.) are wired in `assets/css/app.css` and resolve
to light/dark values via a `dark` class on `<html>`.

## Run it locally

### Prerequisites

- **Elixir 1.18+ / OTP 27+** — `asdf install elixir 1.19.x` or your
  distro's package
- **Node 22+** — Phoenix's asset pipeline calls `npm` (the project
  is on npm not pnpm because `phoenix_vite` hardcodes the npm binary)
- **Postgres 15+** — easiest is Docker:
  ```sh
  docker run -d --name mixwave-pg \
    -e POSTGRES_PASSWORD=postgres -e POSTGRES_USER=postgres \
    -p 5432:5432 postgres:16-alpine
  ```

The studio doesn't use any external API keys or storage — Tone.js
samples come from public CDN URLs the browser fetches directly.

### First-time setup

```sh
mix setup        # install deps, create db, run migrations, build assets
mix phx.server   # start the server
```

Visit [`localhost:4000`](http://localhost:4000). You're handed an
anonymous identity on first request and dropped into the jam.

### Multi-machine LAN testing

The whole point of v1 is multi-user, so you'll want to test from a
second device:

1. Find this machine's LAN IP: `hostname -I`
2. Open ports 4000 (Phoenix) + 5173 (Vite dev server) in your
   firewall. With `firewalld`:
   ```sh
   sudo firewall-cmd --add-port=4000/tcp
   sudo firewall-cmd --add-port=5173/tcp
   ```
3. Start the server with the LAN IP exposed:
   ```sh
   DEV_LAN_HOST=<your-lan-ip> mix phx.server
   ```
4. From the other device, browse to `http://<your-lan-ip>:4000`.

Both devices land in the same global studio. Tap a drum on one,
hear it on the other.

### Useful commands

```sh
mix setup            # install deps + db + assets
mix ecto.reset       # drop + recreate db
mix phx.server       # dev server with Vite hot reload
mix assets.build     # one-shot Vite build
mix assets.deploy    # production asset build + digest
mix test             # run the test suite
mix precommit        # compile --warnings-as-errors + format + test
```

## Layout

```
mixwave/
├── BRAINSTORM.md                 goal + talk shape + locked decisions
├── README.md                     this file
├── lib/
│   ├── mixwave/
│   │   ├── application.ex        supervisor tree
│   │   ├── repo.ex
│   │   ├── accounts/             anonymous users + name generator + sweeper GenServer
│   │   ├── accounts.ex           context: create / get / touch / sweep
│   │   ├── studio/
│   │   │   └── room.ex           supervised GenServer holding recent note events
│   │   └── studio.ex             context: subscribe / broadcast_note
│   └── mixwave_web/
│       ├── components/           layouts.ex, core_components.ex (HEEX)
│       ├── channels/presence.ex  Phoenix.Presence module
│       ├── live/
│       │   └── studio_live.ex    the whole user-facing app
│       ├── plugs/
│       │   └── ensure_anon_user.ex  cookie-based anon identity
│       ├── router.ex
│       └── user_auth.ex          LV on_mount that injects current_user
├── assets/
│   ├── css/app.css               Tailwind v4 + shadcn-vue tokens
│   ├── js/app.js                 LiveSocket + LiveVue bootstrap
│   ├── vue/
│   │   ├── Studio.vue            single live_vue island; v-ifs the active pad
│   │   ├── instruments/
│   │   │   ├── DrumPad.vue       3 flavors: synth / 808 / acoustic
│   │   │   ├── KeyboardPad.vue   3 flavors: synth / lead / piano (sampled)
│   │   │   └── GuitarPad.vue     3 flavors: synth / pluck (K-S) / acoustic (sampled)
│   │   ├── lib/
│   │   │   ├── audio.ts          Tone.js engine registry — 9 engines
│   │   │   └── utils.ts          cn() helper
│   │   ├── components/ui/        shadcn-vue starter components
│   │   └── index.ts              live_vue entry
│   └── vite.config.mjs
├── priv/repo/migrations/         only anonymous_users — jams are ephemeral
├── config/
└── test/
```

## License

Personal / learning project. See [BRAINSTORM.md](./BRAINSTORM.md)
§1 for the audience and goal.
