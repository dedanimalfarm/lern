#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
source "$ROOT_DIR/scripts/verify/helpers.sh"

need_bin curl
need_bin jq
require_api_up

# Экспортированная коллекция с собственным запросом
COL=/tmp/api-lab/m04-collection.json
require_valid_json_file "$COL"
SCHEMA=$(jq -r '.info.schema' "$COL" 2>/dev/null || true)
[[ "$SCHEMA" == *"v2.1.0"* ]] || fail "$COL: не формат Collection v2.1 (Export -> v2.1)"
REQS=$(jq '[.. | objects | select(has("request"))] | length' "$COL" 2>/dev/null || true)
[[ "$REQS" =~ ^[0-9]+$ && "$REQS" -ge 8 ]] \
  || fail "$COL: запросов $REQS, ожидалось >= 8 (7 из курса + ваш «Решить тикет…»)"
OWN=$(jq '[.. | objects | select(has("request"))
  | select((.name // "") | test("ешить|esolve"))
  | select(.request.method == "PATCH")
  | select((.event // []) | map(.listen) | index("test") != null)] | length' "$COL" 2>/dev/null || true)
[[ "$OWN" =~ ^[0-9]+$ && "$OWN" -ge 1 ]] \
  || fail "$COL: нет PATCH-запроса «Решить тикет…» с тестами (tasks/02-own-request.md)"
ok "экспортированная коллекция: $REQS запросов, свой PATCH с тестами на месте"

# Цепочка реально доведена до resolved
RESOLVED=$(curl -s -G "$API/api/v1/tickets" --data-urlencode 'q=Создано из Postman' \
  | jq '[.items[] | select(.status=="resolved")] | length' 2>/dev/null || true)
[[ "$RESOLVED" =~ ^[0-9]+$ && "$RESOLVED" -ge 1 ]] \
  || fail "нет тикета «Создано из Postman» в статусе resolved — цепочка не прогнана"
ok "цепочка Создать -> В работу -> Решить выполнена (тикет resolved)"

# Починенная broken-коллекция
FIX=/tmp/api-lab/m04-fixed-collection.json
require_valid_json_file "$FIX"
BADPATH=$(jq '[.. | objects | select(has("request"))
  | .request.url.raw // "" | select(test("/api/v1/ticket([^s]|$)"))] | length' "$FIX" 2>/dev/null || true)
[[ "$BADPATH" == "0" ]] || fail "$FIX: остался путь /api/v1/ticket (ед. число) — починка 1 не сделана"
CTOK=$(jq '[.. | objects | select(has("request")) | select(.request.method=="POST")
  | select((.request.body.options.raw.language // "") == "json"
           or ([.request.header[]? | select((.key|ascii_downcase)=="content-type")
                | select(.value | test("json"))] | length) > 0)] | length' "$FIX" 2>/dev/null || true)
[[ "$CTOK" =~ ^[0-9]+$ && "$CTOK" -ge 1 ]] \
  || fail "$FIX: POST всё ещё без JSON Content-Type (Body raw -> JSON) — починка 2 не сделана"
ok "broken-коллекция починена (путь /tickets, Body raw -> JSON)"

ok "module 04 verified"
