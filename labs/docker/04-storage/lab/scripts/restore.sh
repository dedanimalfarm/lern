#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Имена бэкапов создаёт сам лаб-скрипт (backup-YYYYmmdd-HHMMSS.sql) — пробелов и
# спецсимволов в них не бывает, поэтому ls тут безопаснее и читаемее find.
# shellcheck disable=SC2012
latest="$(ls -1 "$LAB_DIR"/backups/*.sql 2>/dev/null | tail -n 1 || true)"
if [[ -z "$latest" ]]; then
  echo 'no backup files found'
  exit 1
fi

docker compose -f "$LAB_DIR/compose.yaml" exec -T db psql -U appuser -d appdb -c 'TRUNCATE TABLE notes;' >/dev/null
docker compose -f "$LAB_DIR/compose.yaml" exec -T db psql -U appuser -d appdb < "$latest"

echo "restored: $latest"
