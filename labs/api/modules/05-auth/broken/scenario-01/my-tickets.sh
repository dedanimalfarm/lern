#!/usr/bin/env bash
# Скрипт смены: выгрузить «мои тикеты в работе» в /tmp/api-lab/m05-my-tickets.json.
# Жалоба: «после перевода API на токены скрипт перестал работать (401)».
# В скрипте две ошибки — диагностируйте по error.code в ответах.
set -euo pipefail

API="http://localhost:8080"
OUT="/tmp/api-lab/m05-my-tickets.json"

TOKEN=$(curl -s -X POST -u support:support123 "$API/api/v1/auth/token" | jq -r '.token')

curl -s -H "Authorization: $TOKEN" \
  "$API/api/v1/tickets?status=in_progress&per_page=50" > "$OUT"

echo "сохранено в $OUT:"
jq -c '.items[]? | {id, title}' "$OUT"
