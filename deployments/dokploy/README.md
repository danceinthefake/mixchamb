# Dokploy deployment

Self-hosted PaaS-style deploy via [Dokploy](https://dokploy.com).
Dokploy handles the reverse proxy (Traefik), SSL, Postgres, env
management, and auto-deploy-on-push for you, in exchange for
running Dokploy itself on a VPS.

## When this fits

- You already run Dokploy for other apps and want mixchamb in
  the same dashboard.
- You want git-push-to-deploy UX without setting up your own GH
  Actions + SSH + symlink swap.
- You want a UI for env vars, logs, and rollbacks instead of
  `ssh + journalctl + ln -sfn`.

If none of the above apply, `linux-host/` or `docker-compose/`
have lower operational footprint than "install Dokploy then
install mixchamb."

## Honest caveat on this guide

Dokploy's UI and config schema have evolved across versions, and
I'm describing the typical flow rather than pinning to a
specific Dokploy release. The Dockerfile here is current and
correct; the UI-side configuration may have moved tabs / renamed
fields by the time you read this. Adapt to whatever the current
Dokploy version shows you. The conceptual model — application,
linked database service, env vars, domain, healthcheck — is
stable.

## Layout

```
dokploy/
├── README.md                    # this file
├── Dockerfile                   # what Dokploy builds
└── env.example                  # reference for the Environment tab
```

No `docker-compose.yml` (Dokploy generates one internally), no
GitHub Action (Dokploy's git webhook replaces it), no systemd
units (Dokploy/Docker manage the process tree).

## First-time install

### 0. Install Dokploy on your VPS (one-time, once per host)

Follow [Dokploy's install docs](https://docs.dokploy.com).
Roughly: a single shell-installed binary, a Postgres for
Dokploy itself, a Traefik reverse proxy, and the web UI on a
chosen port. Don't expose the UI to the public internet
without auth — put it behind your own Cloudflare Access or
SSH-tunnel-only.

### 1. Create a Postgres service in Dokploy

Dokploy → Project → **Create Service** → **Postgres**.
- Version: `16`
- Database name: `mixchamb_prod`
- User: `mixchamb`
- Password: generate a strong one, save it

Dokploy will create a Postgres container with a persistent
volume managed by Dokploy itself.

### 2. Create the mixchamb application

Dokploy → Project → **Create Service** → **Application**.

- **Source:** git
  - Repository: your `mixchamb` repo URL
  - Branch: `main` (or whichever branch you cut releases from)
  - Build path: `/` (repo root — the Dockerfile expects to see
    `mix.exs` at its build context)
- **Build type:** Dockerfile
  - Dockerfile path: `deployments/dokploy/Dockerfile`
- **Domain:** your public hostname (e.g. `mixchamb.com`)
- **Internal port:** `4000`
- **Health check:** `GET /` → expect `200`
- **Environment:** paste the variables from `env.example`,
  filling in real values. Skip `DATABASE_URL` — see next step.

### 3. Link the Postgres service to the app

Dokploy → mixchamb application → **Environment** → **Link
Database**. Select the Postgres service from step 1. Dokploy
will inject `DATABASE_URL` (or equivalent — check the variable
name your Dokploy version uses; older versions used
`POSTGRES_HOST` / `POSTGRES_PORT` separately).

If your Dokploy version doesn't inject `DATABASE_URL` directly,
construct it manually in the Environment tab using the
Postgres service's internal hostname (Dokploy shows this in
the service detail view):

```
DATABASE_URL=ecto://mixchamb:<password>@<postgres-service-name>:5432/mixchamb_prod
```

### 4. Set the deploy trigger

Dokploy → application → **Settings** → **Auto Deploy**:
- Enable webhook on git push, OR
- Use Dokploy's manual "Deploy" button per release

For tag-based deploys, configure the webhook to fire on
`refs/tags/v*` only — same safety rationale as the GH Actions
flow in the other deployment options (don't auto-deploy
arbitrary branch pushes from a public repo).

### 5. Cloudflare Tunnel (recommended)

Two options:

**Option A — Tunnel as a Dokploy service** (preferred, keeps
parity with the other deployment options):
- Create a tunnel in the Cloudflare Zero Trust dashboard, route
  the public hostname → `http://mixchamb-app:4000` (the
  Dokploy-internal service name for your application).
- Dokploy → **Create Service** → **Custom Docker Service**:
  - Image: `cloudflare/cloudflared:latest`
  - Command: `tunnel --no-autoupdate run --token <YOUR_TOKEN>`
  - Network: same Docker network as the mixchamb app (Dokploy
    handles this automatically if services are in the same
    project).

**Option B — Dokploy's built-in Traefik with public origin IP:**
- Skip the tunnel. Dokploy's Traefik gets a public Let's
  Encrypt cert and serves `https://mixchamb.com` directly.
- Cheaper to set up but exposes your VPS IP. If you take this
  path, firewall `:443` to Cloudflare's IP ranges and rely on
  Cloudflare proxied DNS for DDoS protection.

### 6. Trigger the first deploy

Either push to the configured branch (if webhook is enabled)
or click **Deploy** in the UI. Watch the build logs in
Dokploy → application → **Deployments**.

## Ongoing operations

| Task | How |
|---|---|
| Deploy a new version | `git push` (with webhook on) or click **Deploy** in Dokploy. |
| Rollback | Dokploy → application → **Deployments** → pick a previous successful deploy → **Redeploy**. |
| View logs | Dokploy → application → **Logs** (live tail) |
| Restart | Dokploy → application → **Settings** → **Restart** |
| Open a shell | Dokploy → application → **Console** (web shell into the container) |
| Migrations | Run automatically on container start (see Dockerfile `CMD`). For one-off `mix release` commands, use the Console: `/app/bin/mixchamb eval "..."`. |
| Backups | Dokploy → Postgres service → **Backups** tab. Configure schedule + S3/B2 destination + retention. Test the restore path before launch. |

## Trade-offs

- **Pro:** Polished UI for the operations you do most
  (deploy, rollback, env edit, log tail).
- **Pro:** Postgres + reverse proxy + SSL are Dokploy-managed
  — you don't write the compose or systemd files.
- **Con:** You're running Dokploy itself. Patching, upgrading,
  and securing the Dokploy install is your job. That's a
  meaningful new surface area vs `linux-host/`.
- **Con:** Less visibility into what's actually happening on
  the box. When something breaks below the UI layer, you're
  debugging Dokploy + Docker + Traefik instead of just Docker
  or just systemd.

## Monitoring

- **Built-in:** Dokploy shows live logs, basic CPU/mem
  metrics per service, deploy history.
- **External alerting:** same as the other options — wire
  UptimeRobot + Sentry + healthchecks (for backups) at the
  shared Telegram bot. Dokploy's internal alerting (if any in
  your version) can also point at the same bot.

## Public-repo safety

Dokploy connects to your git repo. If your repo is public:
- Use webhook-based auto-deploy only with a path filter
  (tags-only, or specific branch) — don't auto-deploy on
  arbitrary PR merges.
- Dokploy stores secrets (env vars, DB password) in its own
  encrypted store. They never need to be in the git repo.
- Restrict Dokploy UI access (Cloudflare Access, IP allowlist,
  or SSH-tunnel-only).
