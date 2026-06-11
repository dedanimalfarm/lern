#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
source "$ROOT_DIR/scripts/verify/helpers.sh"

need_bin curl
need_bin jq
require_api_up

# Стенд в режиме token
require_jq '.auth_mode' "token" "$API/api/v1/_lab/state"

# Без токена доступ закрыт
require_http 401 "$API/api/v1/tickets"
ok "без токена API закрыт (401)"

# Токен-флоу и роли работают
VT=$(curl -s -X POST -u support:support123 "$API/api/v1/auth/token" \
  | jq -r '.access_token' 2>/dev/null || true)
[[ "$VT" == *.*.* ]] || fail "не удалось получить токен support — стенд в token-режиме?"
require_http 200 -H "Authorization: Bearer $VT" "$API/api/v1/whoami"
require_http 403 -X DELETE -H "Authorization: Bearer $VT" "$API/api/v1/tickets/1"
ok "токен-флоу работает (agent: whoami 200, DELETE 403)"

# Задание 01: токен сохранён и payload декодирован
TOK_FILE=/tmp/api-lab/m05-token.txt
[[ -s "$TOK_FILE" ]] || fail "нет файла $TOK_FILE — tasks/01-token-flow.md"
DOTS=$(tr -cd '.' < "$TOK_FILE" | wc -c || true)
[[ "$DOTS" == "2" ]] || fail "$TOK_FILE: токен должен состоять из 3 частей через точку"
PAYLOAD_OK=$(python3 - "$TOK_FILE" <<'EOF' 2>/dev/null || true
import base64, json, sys
tok = open(sys.argv[1]).read().strip()
p = tok.split(".")[1]
claims = json.loads(base64.urlsafe_b64decode(p + "=" * (-len(p) % 4)))
print("yes" if "sub" in claims and "exp" in claims else "no")
EOF
)
[[ "$PAYLOAD_OK" == "yes" ]] || fail "$TOK_FILE: payload не декодируется или нет sub/exp"
ok "токен сохранён и структурно валиден"

PJ=/tmp/api-lab/m05-jwt-payload.json
require_valid_json_file "$PJ"
SUB=$(jq -r '.sub' "$PJ" 2>/dev/null || true)
EXP=$(jq -r '.exp' "$PJ" 2>/dev/null || true)
[[ -n "$SUB" && "$SUB" != "null" && "$EXP" =~ ^[0-9]+$ ]] \
  || fail "$PJ: ожидались поля sub и exp (число)"
ok "payload JWT декодирован в $PJ (sub=$SUB)"

# Задание 02: доказательство 403
F403=/tmp/api-lab/m05-403.txt
[[ -s "$F403" ]] || fail "нет файла $F403 — tasks/02-401-vs-403.md"
grep -q "403" "$F403" || fail "$F403: нет статуса 403"
grep -q "forbidden" "$F403" || fail "$F403: нет тела с code=forbidden (сохраняйте с -i)"
ok "доказательство 403 собрано"

# Тикет m05 создан аутентифицированным POST
CNT=$(curl -s -H "Authorization: Bearer $VT" "$API/api/v1/tickets?q=m05" \
  | jq -r '.total' 2>/dev/null || true)
[[ "$CNT" =~ ^[0-9]+$ && "$CNT" -ge 1 ]] \
  || fail "тикет с 'm05' в title не найден — создайте его с токеном"
ok "тикет m05 создан через аутентифицированный POST"

# Broken-сценарий: скрипт выгрузил валидный список
MT=/tmp/api-lab/m05-my-tickets.json
require_valid_json_file "$MT"
ITEMS=$(jq '.items | length' "$MT" 2>/dev/null || true)
[[ "$ITEMS" =~ ^[0-9]+$ && "$ITEMS" -ge 1 ]] \
  || fail "$MT: нет .items — broken/scenario-01 не починен (внутри всё ещё ошибка?)"
ok "broken/scenario-01 починен (выгружено тикетов: $ITEMS)"

ok "module 05 verified"
