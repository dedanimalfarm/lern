#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
source "$ROOT_DIR/scripts/verify/helpers.sh"

need_bin curl
need_bin jq
require_api_up

# Стенд должен быть в дефолтном режиме
require_jq '.auth_mode' "off" "$API/api/v1/_lab/state"

# Задание 01: файл заголовков снят через -D
HDR=/tmp/api-lab/m01-headers.txt
[[ -f "$HDR" ]] || fail "нет файла $HDR — задание tasks/01-headers.md"
grep -q "HTTP/1.1 200" "$HDR" || fail "$HDR не содержит 'HTTP/1.1 200'"
grep -qi "x-total-count" "$HDR" || fail "$HDR не содержит X-Total-Count (точно снимали с /api/v1/tickets?)"
ok "заголовки сняты в $HDR"

# Задание 02: тикет с пометкой m01 создан и находится поиском
require_jq_min '.total' 1 "$API/api/v1/tickets?q=m01"
ok "тикет с 'm01' в title существует (POST -> 201 -> GET отработан)"

# Задание 03: каталог статус-кодов собран
CODES=/tmp/api-lab/m01-codes.txt
[[ -f "$CODES" ]] || fail "нет файла $CODES — задание tasks/03-status-codes.md"
for c in 301 400 404 405 415 422; do
  grep -q "^$c " "$CODES" || fail "в $CODES нет строки, начинающейся с '$c '"
done
ok "каталог статус-кодов собран (301/400/404/405/415/422)"

# Broken-сценарий: починенный скрипт реально создал заявку
CNT=$(curl -s -G "$API/api/v1/tickets" --data-urlencode 'q=Заявка из скрипта' \
  | jq -r '.total' 2>/dev/null || true)
[[ "$CNT" =~ ^[0-9]+$ && "$CNT" -ge 1 ]] \
  || fail "заявка 'Заявка из скрипта' не найдена — broken/scenario-01 не починен"
ok "broken/scenario-01 починен (заявка из скрипта создана)"

ok "module 01 verified"
