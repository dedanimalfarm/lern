#!/usr/bin/env bash
# Слепая диагностика: включает СЛУЧАЙНУЮ поломку стенда.
# Фактический режим прячется в /tmp/api-lab/.m06-actual для check.sh —
# НЕ подглядывайте (и в _lab/state тоже: в реальном инциденте его нет).
set -euo pipefail

MODES=(slow error500 badjson wrongct)
MODE=${MODES[RANDOM % ${#MODES[@]}]}

curl -s -X POST http://localhost:8080/api/v1/_lab/fault \
  -H 'Content-Type: application/json' -d "{\"mode\":\"$MODE\"}" >/dev/null

mkdir -p /tmp/api-lab
echo "$MODE" > /tmp/api-lab/.m06-actual

echo "[OK] поломка включена. Диагностируйте, НЕ заглядывая в _lab/state!"
echo "     Диагноз (slow|error500|badjson|wrongct) — первой строкой в /tmp/api-lab/m06-diagnosis.txt"
echo "     Затем: bash $(dirname "$0")/check.sh"
