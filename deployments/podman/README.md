# Podman deployment

Containers managed by systemd via Quadlet. Daemonless, integrates
with the same `OnFailure=` Telegram alerting story as the
`linux-host/` method. Think of this as a hybrid between
`linux-host/` (systemd-native) and `docker-compose/` (containers).

## When this fits

- You want container isolation but resent the Docker daemon
  (rootless model, security posture, supply-chain footprint).
- You like systemd's lifecycle management and want it to manage
  your containers too — `systemctl restart mixchamb` instead of
  `docker compose restart`, logs in `journalctl` natively.
- You're on a Red Hat-family distro where Podman is the
  first-class container runtime (AlmaLinux / Rocky / RHEL / Fedora).

If you'd rather just swap `docker` → `podman` and keep the
compose file, `podman compose` works as a drop-in against the
files in `../docker-compose/`. The Quadlet approach here is more
idiomatic Podman but takes a little more setup.

## Layout

```
podman/
├── README.md                    # this file
├── quadlet/
│   ├── mixchamb.network         # /etc/containers/systemd/
│   ├── pgdata.volume            # /etc/containers/systemd/
│   ├── postgres.container       # /etc/containers/systemd/
│   ├── mixchamb.container       # /etc/containers/systemd/
│   └── cloudflared.container    # /etc/containers/systemd/
├── env/
│   ├── mixchamb.env.example                # /etc/mixchamb.env
│   └── mixchamb-podman.env.example         # /etc/mixchamb-podman.env
└── github-workflows/
    └── deploy.yml                          # copy to .github/workflows/deploy.yml
```

No Dockerfile here — the deploy workflow reuses
`../docker-compose/Dockerfile` as the single source of truth.
The image landing on `ghcr.io` is the same image both methods
consume.

## Prerequisites

- Podman 4.4+ (for Quadlet support). Check: `podman --version`.
  AlmaLinux 9 / Rocky 9 ship Podman 4.x via `dnf install podman`.
- systemd 250+ (any modern distro is fine).
- `cloudflared` token from a tunnel created in the Cloudflare
  Zero Trust dashboard.

## First-time install

1. **Install Podman** (`dnf install -y podman` on RHEL family;
   `apt install -y podman` on Debian/Ubuntu — but Debian's
   Podman version may lag; check Quadlet support).

2. **Create the env files**:
   ```bash
   sudo install -m 600 -o root -g root env/mixchamb.env.example /etc/mixchamb.env
   sudo install -m 600 -o root -g root env/mixchamb-podman.env.example /etc/mixchamb-podman.env
   sudo $EDITOR /etc/mixchamb.env /etc/mixchamb-podman.env
   ```

3. **Install Quadlet files** to `/etc/containers/systemd/`:
   ```bash
   sudo install -d -m 755 /etc/containers/systemd
   sudo install -m 644 quadlet/* /etc/containers/systemd/
   # Edit Image= in mixchamb.container to point at YOUR ghcr.io repo:
   sudo $EDITOR /etc/containers/systemd/mixchamb.container
   ```

4. **Generate + start the units**. Quadlet runs as part of
   `systemctl daemon-reload`; the resulting services are
   `<filename>.service` (so `mixchamb.container` becomes
   `mixchamb.service`).
   ```bash
   sudo systemctl daemon-reload
   sudo systemctl enable --now postgres.service
   sudo systemctl enable --now cloudflared.service
   sudo systemctl enable --now mixchamb.service
   ```

5. **(Optional) Wire up the same `OnFailure=` Telegram pattern**
   from `../linux-host/`. Copy
   `../linux-host/systemd/notify-telegram@.service` and
   `../linux-host/scripts/notify-telegram` to the standard
   locations — the Quadlet `.container` files in this directory
   already reference `OnFailure=notify-telegram@%n.service`.

6. **Create the GH Actions deploy user** (same shape as
   `../linux-host/` step 11 of `bootstrap.sh`, but the sudo
   command is `systemctl restart mixchamb.service` instead of
   `systemctl restart mixchamb`):
   ```bash
   useradd --create-home --shell /bin/bash deploy
   # ... paste deploy public key into ~/.ssh/authorized_keys ...
   cat > /etc/sudoers.d/deploy <<'EOF'
   deploy ALL=(root) NOPASSWD: /usr/bin/systemctl restart mixchamb.service
   deploy ALL=(root) NOPASSWD: /usr/bin/systemctl status mixchamb.service
   EOF
   chmod 440 /etc/sudoers.d/deploy
   ```

7. **Cut a release**: `git tag -a v0.1.0 -m "v0.1.0" && git push origin v0.1.0`
   — CI builds the image, pushes to ghcr.io, the workflow SSHes
   in and runs `podman pull && systemctl restart mixchamb.service`.

## Ongoing operations

| Task | How |
|---|---|
| Deploy a new version | `git tag -a vX.Y.Z && git push origin vX.Y.Z`. PullPolicy=always on mixchamb.container means restart pulls the new image. |
| Rollback | `podman pull ghcr.io/<owner>/mixchamb:vOLD && podman tag ghcr.io/<owner>/mixchamb:vOLD ghcr.io/<owner>/mixchamb:latest && sudo systemctl restart mixchamb.service`. Or pin Image= in `.container` to a specific tag and reload. |
| View logs | `journalctl -u mixchamb -f` (same as linux-host — Podman pipes container stdout/stderr to journald natively) |
| Restart | `sudo systemctl restart mixchamb.service` |
| Open a shell | `podman exec -it mixchamb /app/bin/mixchamb remote` |
| One-off migration | `podman exec mixchamb /app/bin/mixchamb eval "Mixchamb.Release.migrate"` (runs automatically on container start too) |
| Inspect a container | `podman inspect mixchamb` / `podman top mixchamb` |
| Restore from backup | `b2 download-file-by-name mixchamb-backups daily/<ts>.sql.gz -` piped into `podman exec -i postgres psql -U mixchamb mixchamb_prod`. Drill before launch. |

## Trade-offs

| vs `linux-host/` | vs `docker-compose/` |
|---|---|
| **Pro:** Container isolation without writing a Dockerfile by hand (well, you reuse one — but build/run are container-native). | **Pro:** No daemon — rootless, no `/var/run/docker.sock` to protect, smaller supply-chain surface. |
| **Pro:** Image is reproducible; same artifact runs locally + prod. | **Pro:** systemd-native — `journalctl`, `OnFailure=`, dependency ordering all work as you'd expect from `linux-host/`. |
| **Con:** Extra layer (Podman) to keep patched. systemd alone would handle process lifecycle for free. | **Con:** Tooling around Podman is younger than around Docker (less Stack Overflow coverage, occasional rough edges). |
| **Con:** Quadlet API is recent (~2023); long-tail bugs still being shaken out. | **Con:** `podman compose` works but isn't a perfect Docker Compose clone — corner-case bugs differ. |

## Monitoring

Identical layering to `linux-host/`. Quadlet-generated services
participate in the same systemd ecosystem:

- `OnFailure=notify-telegram@%n.service` on every `.container`
  file (already set) — crashes ping Telegram via the
  `linux-host/` notify-telegram template unit.
- UptimeRobot, healthchecks.io, Sentry — wire to the same bot.
- Container healthchecks are declared in the `.container` files
  themselves (`HealthCmd=`, `HealthInterval=`).
- `systemctl status mixchamb.service` shows the same active /
  failed states; `journalctl -u mixchamb` shows container logs.

## Public-repo safety

Same rules as the other methods:
- Deploy workflow on `push: tags: ['v*']` + `workflow_dispatch`
  only. Never `pull_request`.
- All secrets in GitHub Actions secrets.
- Deploy user on the host has sudo only for `systemctl restart
  mixchamb.service` / `status`.
