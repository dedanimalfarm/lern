#!/usr/bin/env bash
# Исправленный скрипт смены. Было две ошибки:
#   1. 401 missing_token: заголовок был "Authorization: $TOKEN" —
#      без схемы. Серверу нужен "Authorization: Bearer <токен>"
#      (это видно и в WWW-Authenticate ответа: Bearer).
#   2. 401 malformed_token: jq доставал '.token', а эндпоинт возвращает
#      '.access_token' (см. доку POST /api/v1/auth/token) — в TOKEN
#      лежал null, и сервер получал "Bearer null".
set -euo pipefail

API="http://localhost:8080"
OUT="/tmp/api-lab/m05-my-tickets.json"

TOKEN=$(curl -s -X POST -u support:support123 "$API/api/v1/auth/token" | jq -r '.access_token')

curl -s -H "Authorization: Bearer $TOKEN" \
  "$API/api/v1/tickets?status=in_progress&per_page=50" > "$OUT"

echo "сохранено в $OUT:"
jq -c '.items[]? | {id, title}' "$OUT"
