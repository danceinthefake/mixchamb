# Docker Compose deployment

Phoenix + Postgres + Cloudflare Tunnel as containers on a single
host. Works on any Linux box with Docker 24+ and the
`docker compose` plugin.

## Layout

```
docker-compose/
├── README.md                    # this file
├── Dockerfile                   # multi-stage build of the Phoenix release
├── docker-compose.yml           # app + postgres + cloudflared + backup
├── backup.sh                    # daily pg_dump → B2, mounted into backup container
├── .env.example                 # copy to .env, never commit
└── github-workflows/
    └── deploy.yml               # copy to .github/workflows/deploy.yml
```

## First-time install (per fresh host)

1. **Install Docker + Compose** on the host. On Debian/Ubuntu:
   ```bash
   curl -fsSL https://get.docker.com | sh
   # docker compose plugin is included in modern installs.
   ```
2. **Create the deploy user** (non-root, in the `docker` group):
   ```bash
   useradd -m -s /bin/bash -G docker deploy
   mkdir -p /home/deploy/.ssh && chmod 700 /home/deploy/.ssh
   # Paste the GH Actions deploy public key:
   echo "ssh-ed25519 AAAA... deploy@github-actions" \
     > /home/deploy/.ssh/authorized_keys
   chmod 600 /home/deploy/.ssh/authorized_keys
   chown -R deploy:deploy /home/deploy/.ssh
   ```
3. **Clone (or copy) the deployments tree** to the host:
   ```bash
   sudo -u deploy git clone https://github.com/<owner>/mixchamb.git /home/deploy/mixchamb
   cd /home/deploy/mixchamb/deployments/docker-compose
   ```
4. **Create `.env`** from the template:
   ```bash
   cp .env.example .env
   # Edit .env, fill in real values.
   chmod 600 .env
   ```
5. **Create the Cloudflare Tunnel** in the Cloudflare Zero Trust
   dashboard (Networks → Tunnels → Create a tunnel → "Cloudflared"
   type). Route the public hostname to `http://app:4000`. Copy
   the printed token into `.env` as `CLOUDFLARE_TUNNEL_TOKEN`.
6. **Bring up the stack**:
   ```bash
   docker compose --env-file .env up -d --build
   ```
   First `up` builds the image locally. Subsequent deploys
   pull from `ghcr.io` (see workflow below).
7. **Cut a release**: `git tag -a v0.1.0 -m "v0.1.0" && git push origin v0.1.0`
   — the GitHub Action handles the rest.

## Ongoing operations

| Task | How |
|---|---|
| Deploy a new version | `git tag -a vX.Y.Z -m "vX.Y.Z" && git push origin vX.Y.Z`. CI builds + pushes the image to `ghcr.io`, then SSHes and runs `docker compose pull app && docker compose up -d --no-deps app`. |
| Rollback | `docker compose pull && docker compose up -d` won't roll back — use `docker compose up -d --no-deps -e IMAGE_TAG=v<previous>` or edit `image:` in compose file. Cleaner: pin `image: ghcr.io/<owner>/mixchamb:vX.Y.Z` in compose and bump on each deploy. |
| View logs | `docker compose logs -f app` (or `postgres`, `cloudflared`) |
| Restart app | `docker compose restart app` |
| Open a shell in the app | `docker compose exec app /app/bin/mixchamb remote` |
| Run a one-off migration | `docker compose exec app /app/bin/mixchamb eval "Mixchamb.Release.migrate"` (also runs automatically on container start) |
| Restore from backup | `b2 download-file-by-name mixchamb-backups daily/<ts>.sql.gz -` piped into `docker compose exec -T postgres psql -U mixchamb mixchamb_prod`. Drill before launch. |

## Running with Podman instead of Docker

`podman compose --env-file .env up -d --build` works as a
drop-in against the same `docker-compose.yml` (Podman 4.x
ships its own compose implementation). You give up the
systemd-native lifecycle that the `../podman/` Quadlet
approach provides, but you gain the rootless / daemonless
posture without rewriting any configs. Pick `../podman/` if
you want full systemd integration; stay here if you just want
"Docker without Docker."

## Trade-offs vs `linux-host/`

- **Pro:** Same compose stack works locally and in prod —
  `docker compose up` on a laptop gives you the full app +
  Postgres + tunnel.
- **Pro:** Image is reproducible; SHA pinning catches "works on
  my machine" before it ships.
- **Con:** Extra layer (Docker daemon) to keep patched and
  running. systemd would manage processes for free.
- **Con:** Postgres in a container with a named volume is fine
  for small data, but you're trusting Docker to never lose the
  volume. Daily off-box backups are non-negotiable here.

## Monitoring

The systemd `OnFailure=` story doesn't apply — Docker restarts
crashed containers on its own (`restart: unless-stopped`). For
visibility you'd want:

- **UptimeRobot** — HTTP ping on the public URL (same as
  `linux-host/`).
- **healthchecks.io** — `backup` service pings on each
  successful upload.
- **Sentry** — Elixir SDK inside the app container, DSN via
  env (same wiring as `linux-host/`, just configured in the
  app source).
- **Docker healthchecks** — already in the compose file (`app`
  has an HTTP healthcheck, `postgres` has `pg_isready`).
  `docker compose ps` shows the health column.
- **Optional: Watchtower** — auto-restart containers on image
  push if you want push-based deploys instead of the GH Action.
  Adds another moving part.

Telegram alerting still works — point UptimeRobot, healthchecks,
and Sentry at the same bot/chat ID.

## Public-repo safety (the deploy workflow)

Same rules as `linux-host/`:
- `push: tags: ['v*']` + `workflow_dispatch` only. **Never**
  `pull_request`.
- All secrets in GitHub Actions secrets.
- Deploy user on the host is in the `docker` group but is not
  root; sudo isn't needed for `docker compose` operations.

`ghcr.io` packages: the workflow pushes images to GitHub
Container Registry under your repo. Make the package public if
you want anyone to pull (default is "inherits from repo", which
is public when the repo is public).
