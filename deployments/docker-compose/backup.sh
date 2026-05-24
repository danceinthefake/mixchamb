#!/bin/sh
# Daily backup script run by the `backup` container in
# docker-compose.yml. Reads Postgres + B2 + healthchecks settings
# from the container env.
set -eu

TS=$(date -u +%Y%m%dT%H%M%SZ)
FILE=/tmp/mixchamb-${TS}.sql.gz

PGPASSWORD="$POSTGRES_PASSWORD" pg_dump \
  -U mixchamb -h postgres mixchamb_prod \
  | gzip > "$FILE"

b2 account authorize "$B2_APPLICATION_KEY_ID" "$B2_APPLICATION_KEY"
b2 file upload "$B2_BUCKET" "$FILE" "daily/${TS}.sql.gz"
rm "$FILE"

# Heartbeat — healthchecks.io fires Telegram if no ping in 26h.
curl -sf -m 10 --retry 3 "$HEALTHCHECKS_BACKUP_URL" >/dev/null
