#!/usr/bin/env bash
# One-time per-fresh-host setup for a mixchamb VPS.
#
# Target: AlmaLinux 9, SSH on :22, outbound internet, run as root.
#
# Before running: fill in the placeholders in env/*.example, then
# `chmod 600` and place them at /etc/mixchamb.env and
# /etc/mixchamb-env-cron. Also paste the GH Actions deploy public
# key into the placeholder below.

set -euo pipefail

# -- 0. Sanity ----------------------------------------------------
if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root." >&2
  exit 1
fi

DEPLOYMENTS_DIR="$(cd "$(dirname "$0")" && pwd)"

# -- 1. Base packages ---------------------------------------------
dnf update -y
dnf install -y postgresql16-server postgresql16-contrib \
               firewalld policycoreutils-python-utils \
               curl tar cronie

# -- 2. Cloudflared (RPM from Cloudflare) -------------------------
curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-x86_64.rpm \
  -o /tmp/cloudflared.rpm
dnf install -y /tmp/cloudflared.rpm

# -- 3. Postgres init + start -------------------------------------
postgresql-setup --initdb
systemctl enable --now postgresql-16

read -rsp "DB password for the mixchamb role (will not echo): " DB_PASS
echo
sudo -u postgres psql -c "CREATE USER mixchamb WITH PASSWORD '${DB_PASS}';"
sudo -u postgres psql -c "CREATE DATABASE mixchamb_prod OWNER mixchamb;"

# -- 4. App user + dirs -------------------------------------------
useradd --system --no-create-home --shell /sbin/nologin mixchamb
mkdir -p /opt/mixchamb /opt/mixchamb-releases /var/log/mixchamb /etc/cloudflared
chown mixchamb:mixchamb /opt/mixchamb /opt/mixchamb-releases /var/log/mixchamb

# -- 5. Firewall — only SSH inbound, everything outbound (tunnel) -
systemctl enable --now firewalld
firewall-cmd --add-service=ssh --permanent
firewall-cmd --reload

# -- 6. SELinux — leave enforcing, audit2allow on first run -------
# Expect AVC denials on first release. Resolve with audit2allow,
# do NOT setenforce 0 long-term.

# -- 7. Cloudflare Tunnel -----------------------------------------
echo
echo ">>> Logging in to Cloudflare. A browser URL will print —"
echo ">>> open it on your laptop, complete the auth flow."
cloudflared tunnel login
cloudflared tunnel create mixchamb

read -rp "Public hostname (e.g. mixchamb.com): " PUBLIC_HOSTNAME
cloudflared tunnel route dns mixchamb "$PUBLIC_HOSTNAME"

echo ">>> Update /etc/cloudflared/config.yml with the tunnel UUID"
echo ">>> printed above + the hostname you just entered."
install -m 644 -o root -g root \
  "$DEPLOYMENTS_DIR/cloudflared/config.yml.example" \
  /etc/cloudflared/config.yml
echo ">>> Now edit /etc/cloudflared/config.yml before continuing."
read -rp "Press enter when /etc/cloudflared/config.yml is filled in. "

# -- 8. Systemd units ---------------------------------------------
install -m 644 -o root -g root \
  "$DEPLOYMENTS_DIR/systemd/mixchamb.service" \
  /etc/systemd/system/mixchamb.service
install -m 644 -o root -g root \
  "$DEPLOYMENTS_DIR/systemd/cloudflared.service" \
  /etc/systemd/system/cloudflared.service
install -m 644 -o root -g root \
  "$DEPLOYMENTS_DIR/systemd/notify-telegram@.service" \
  /etc/systemd/system/notify-telegram@.service
install -d -m 755 -o root -g root \
  /etc/systemd/system/postgresql-16.service.d
install -m 644 -o root -g root \
  "$DEPLOYMENTS_DIR/systemd/postgresql-16.service.d/onfailure.conf" \
  /etc/systemd/system/postgresql-16.service.d/onfailure.conf

# -- 9. Ops scripts -----------------------------------------------
install -m 755 -o root -g root \
  "$DEPLOYMENTS_DIR/scripts/mixchamb-deploy" /usr/local/bin/mixchamb-deploy
install -m 755 -o root -g root \
  "$DEPLOYMENTS_DIR/scripts/notify-telegram" /usr/local/bin/notify-telegram
install -m 755 -o root -g root \
  "$DEPLOYMENTS_DIR/scripts/backup-mixchamb.sh" /usr/local/bin/backup-mixchamb.sh
install -m 755 -o root -g root \
  "$DEPLOYMENTS_DIR/scripts/disk-check" /etc/cron.weekly/disk-check

# Backup cron entry (runs as postgres so pg_dump trusts the
# peer-auth local socket without prompting).
cat > /etc/cron.d/mixchamb-backup <<'EOF'
0 3 * * * postgres /usr/local/bin/backup-mixchamb.sh
EOF
chmod 644 /etc/cron.d/mixchamb-backup
systemctl enable --now crond

# -- 10. Env files ------------------------------------------------
if [ ! -f /etc/mixchamb.env ]; then
  install -m 600 -o root -g mixchamb \
    "$DEPLOYMENTS_DIR/env/mixchamb.env.example" \
    /etc/mixchamb.env
  echo ">>> Edit /etc/mixchamb.env now, then re-run this script step."
  read -rp "Press enter when /etc/mixchamb.env is filled in. "
fi

if [ ! -f /etc/mixchamb-env-cron ]; then
  install -m 600 -o root -g root \
    "$DEPLOYMENTS_DIR/env/mixchamb-env-cron.example" \
    /etc/mixchamb-env-cron
  echo ">>> Edit /etc/mixchamb-env-cron now, then re-run this step."
  read -rp "Press enter when /etc/mixchamb-env-cron is filled in. "
fi

# -- 11. Deploy user ----------------------------------------------
# Dedicated low-priv account that GH Actions SSHes into. Owns
# nothing critical except writes to releases dir; sudo locked to
# a single restart command. Leaked key = "attacker can restart
# mixchamb", not "attacker owns the box."
useradd --create-home --shell /bin/bash --groups mixchamb deploy
install -d -m 700 -o deploy -g deploy /home/deploy/.ssh

echo
echo ">>> Paste the GH-Actions deploy public key (matching the"
echo ">>> DEPLOY_SSH_KEY secret in the repo). Hit Ctrl-D when done."
cat > /home/deploy/.ssh/authorized_keys
chmod 600 /home/deploy/.ssh/authorized_keys
chown deploy:deploy /home/deploy/.ssh/authorized_keys

cat > /etc/sudoers.d/deploy <<'EOF'
deploy ALL=(root) NOPASSWD: /usr/bin/systemctl restart mixchamb
deploy ALL=(root) NOPASSWD: /usr/bin/systemctl status mixchamb
EOF
chmod 440 /etc/sudoers.d/deploy
visudo -c

# Releases dir — setgid so files extracted by deploy inherit the
# mixchamb group, letting the mixchamb service read them.
chmod 2775 /opt/mixchamb-releases

# -- 12. Enable units ---------------------------------------------
systemctl daemon-reload
systemctl enable --now cloudflared
systemctl enable mixchamb        # starts on first deploy when /opt/mixchamb exists

echo
echo "Bootstrap complete. Now:"
echo "  1. On your laptop: git tag -a v0.1.0 -m 'v0.1.0' && git push origin v0.1.0"
echo "  2. Watch the GH Actions deploy run."
echo "  3. Hit https://${PUBLIC_HOSTNAME}/ — should serve."
