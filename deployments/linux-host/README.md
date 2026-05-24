# Linux host deployment

systemd + Postgres + cloudflared running directly on a Linux VPS.
No containers, no PaaS layer. Lowest overhead at small scale,
most direct mapping from "what the box is doing" to "what's
written here."

## Supported distros

| Distro | Status | Notes |
|---|---|---|
| AlmaLinux 9 | First-class | Reference distro; `bootstrap.sh` runs as-is. |
| Rocky Linux 9 | First-class | Identical to AlmaLinux for our purposes. |
| Ubuntu 22.04+ | Supported | Swap `dnf` → `apt`, `firewalld` → `ufw`; package names in the table below. |
| Debian 12+ | Supported | Same swaps as Ubuntu. |

systemd unit files, env templates, and ops scripts are
distro-agnostic. The only distro-specific bits are the package
install and firewall commands in `bootstrap.sh` step 1 / 5.

### RHEL-family → Debian-family quick adaptation

| RHEL (Alma/Rocky) | Debian / Ubuntu |
|---|---|
| `dnf install postgresql16-server postgresql16-contrib` | `apt install postgresql-16 postgresql-contrib-16` |
| `postgresql-setup --initdb` | (auto on apt) — cluster created at install time |
| `systemctl enable --now postgresql-16` | `systemctl enable --now postgresql@16-main` |
| `firewalld` / `firewall-cmd --add-service=ssh` | `ufw allow ssh` |
| `dnf install /tmp/cloudflared.rpm` | `dpkg -i /tmp/cloudflared.deb` (use the `.deb` from Cloudflare's releases page) |
| Postgres unit name: `postgresql-16.service` | `postgresql@16-main.service` |

If you're on Debian/Ubuntu, copy `bootstrap.sh` to
`bootstrap-debian.sh`, swap the lines above, run that instead.
The systemd drop-in path also changes — use
`/etc/systemd/system/postgresql@16-main.service.d/onfailure.conf`
instead of the `postgresql-16.service.d/` path.

## Layout

```
linux-host/
├── README.md                    # this file
├── bootstrap.sh                 # one-time per-fresh-host setup
├── systemd/
│   ├── mixchamb.service                          # /etc/systemd/system/
│   ├── cloudflared.service                       # /etc/systemd/system/
│   ├── notify-telegram@.service                  # /etc/systemd/system/
│   └── postgresql-16.service.d/
│       └── onfailure.conf                        # drop-in for the package unit
├── cloudflared/
│   └── config.yml.example                        # /etc/cloudflared/config.yml
├── env/
│   ├── mixchamb.env.example                      # /etc/mixchamb.env (chmod 600)
│   └── mixchamb-env-cron.example                 # /etc/mixchamb-env-cron (chmod 600)
├── scripts/
│   ├── mixchamb-deploy                           # /usr/local/bin/
│   ├── notify-telegram                           # /usr/local/bin/
│   ├── backup-mixchamb.sh                        # /usr/local/bin/
│   └── disk-check                                # /etc/cron.weekly/disk-check
└── github-workflows/
    └── deploy.yml                                # copy to .github/workflows/deploy.yml
```

## First-time install (per fresh host)

1. SSH in as root or a sudoer.
2. Edit `bootstrap.sh` and `env/*.example` placeholders (DB
   password, public hostname, GH Actions deploy SSH public key,
   Telegram bot token + chat ID, healthchecks.io URL, B2 bucket
   name + creds).
3. Run `sudo ./bootstrap.sh`. It will:
   - install base packages + Postgres 16 + cloudflared
   - create `mixchamb` (app) and `deploy` (CI) users
   - copy every file from this directory into the right place on disk
   - log in to Cloudflare and create the named tunnel
   - enable + start every systemd unit
4. Cut a release: `git tag -a v0.1.0 -m "v0.1.0" && git push origin v0.1.0`
   — the GitHub Action handles the rest.

## Ongoing operations

| Task | How |
|---|---|
| Deploy a new version | `git tag -a vX.Y.Z -m "vX.Y.Z" && git push origin vX.Y.Z` — Action does the rest. |
| Rollback | SSH in, `ls /opt/mixchamb-releases/`, `ln -sfn /opt/mixchamb-releases/mixchamb-<old-sha> /opt/mixchamb && sudo systemctl restart mixchamb`. Last 5 releases kept on disk. |
| View logs | `journalctl -u mixchamb -f` (app) / `journalctl -u cloudflared -f` (tunnel) |
| Restart app | `sudo systemctl restart mixchamb` |
| Restore from backup | `b2 download-file-by-name mixchamb-backups daily/<ts>.sql.gz -` piped into `gunzip \| psql` against a fresh DB. Drill this before launch. |
| Rotate Telegram bot | Edit `/etc/mixchamb-env-cron` + the GH Actions secrets, `systemctl daemon-reload` to pick up. |

## Monitoring layers (all $0)

| Layer | Signal | Tool |
|---|---|---|
| systemd `OnFailure=` → Telegram | service crash | local |
| UptimeRobot HTTP ping | end-to-end reachability | external |
| healthchecks.io ping after backup | backup didn't run | external cron-watch |
| Sentry (Elixir SDK) | app exceptions | external |
| Weekly disk-usage cron → Telegram | `/var` filling up | local |
| Phoenix LiveDashboard at `/admin/dashboard` | BEAM internals | eyeball-only |

Telegram bot is the single destination for all external layers.
Set it up once (BotFather → token → private group → chat ID),
wire that bot into UptimeRobot / healthchecks.io / Sentry
integrations and into `/etc/mixchamb-env-cron`.

## Public-repo safety (the deploy workflow)

The deploy workflow at `github-workflows/deploy.yml` is meant to
be copied to `.github/workflows/deploy.yml`. The repo is public,
which is fine if:

- Trigger is `push: tags: ['v*']` + `workflow_dispatch` only.
  Never `pull_request` — that's how malicious PRs exfiltrate
  secrets from public-repo CI.
- All secrets live in GitHub Actions secrets. Fork-PR runs can't
  read them (GitHub policy since 2020).
- The `deploy` user on the host has sudo only for the restart
  commands. Leaked SSH key = "attacker can restart the app," not
  "attacker owns the box."

See `systemd/` and `scripts/` for the corresponding host-side
limits.
