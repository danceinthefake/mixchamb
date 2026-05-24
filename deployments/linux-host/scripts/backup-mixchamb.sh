#!/usr/bin/env bash
# Daily Postgres dump → Backblaze B2, ping healthchecks.io on success.
#
# Install at /usr/local/bin/backup-mixchamb.sh (chmod 755, root:root)
# and schedule via /etc/cron.d/mixchamb-backup:
#
#   0 3 * * * postgres /usr/local/bin/backup-mixchamb.sh
#
# Age-out is handled server-side by a B2 lifecycle rule (cheaper
# than listing + deleting from cron).

set -euo pipefail

# /etc/mixchamb-env-cron provides HEALTHCHECKS_BACKUP_URL,
# B2_BUCKET, B2_APPLICATION_KEY_ID, B2_APPLICATION_KEY.
# shellcheck source=/dev/null
source /etc/mixchamb-env-cron

TS=$(date -u +%Y%m%dT%H%M%SZ)
FILE="/tmp/mixchamb-${TS}.sql.gz"

pg_dump -U mixchamb -h localhost mixchamb_prod | gzip > "$FILE"
b2 upload-file "$B2_BUCKET" "$FILE" "daily/${TS}.sql.gz"
rm "$FILE"

# Heartbeat — healthchecks.io fires Telegram if no ping in 26h
# (window covers the 24h schedule + a 2h grace for slow uploads).
curl -sf -m 10 --retry 3 "${HEALTHCHECKS_BACKUP_URL}" >/dev/null
