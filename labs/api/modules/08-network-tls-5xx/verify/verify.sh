#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
source "$ROOT_DIR/scripts/verify/helpers.sh"

need_bin curl
need_bin jq
require_api_up

# Стенд возвращён в дефолт (за собой убрано)
require_jq '.fault' "none" "$API/api/v1/_lab/state"
ok "стенд в дефолтном режиме (fault=none)"

# Задание 01a: каталог curl exit-кодов сети
NET=/tmp/api-lab/m08-net.txt
[[ -s "$NET" ]] || fail "нет файла $NET — tasks/01-network-tls.md (часть «сеть»)"
for c in 6 7 28; do
  grep -q "^$c " "$NET" || fail "$NET: нет строки, начинающейся с '$c ' (curl exit-код)"
done
ok "каталог curl exit-кодов собран (6/7/28)"

# Задание 01b: TLS-сертификат разобран через s_client/openssl
TLS=/tmp/api-lab/m08-tls.txt
[[ -s "$TLS" ]] || fail "нет файла $TLS — tasks/01-network-tls.md (часть «TLS»)"
grep -qi "localhost" "$TLS" || fail "$TLS: нет CN сертификата (CN=localhost из s_client)"
grep -qiE "notAfter|not after|expire|истека" "$TLS" \
  || fail "$TLS: нет срока действия сертификата (notAfter)"
grep -qiE "\-k|insecure|довер|trust" "$TLS" \
  || fail "$TLS: нет вывода про опасность -k/недоверие (зачем это вообще проверяли?)"
ok "TLS-сертификат разобран (CN, срок, риск -k)"

# Задание 02: триаж 5xx за балансировщиком
FIVE=/tmp/api-lab/m08-5xx.txt
[[ -s "$FIVE" ]] || fail "нет файла $FIVE — tasks/02-5xx-triage.md"
for c in 502 503 504; do
  grep -q "^$c " "$FIVE" || fail "$FIVE: нет строки, начинающейся с '$c '"
done
# Именно 503 — единственный из трёх, кто сам говорит, когда вернуться
grep -E "^503 " "$FIVE" | grep -qi "retry-after" \
  || fail "$FIVE: в строке 503 должно быть про Retry-After (кто говорит, когда вернуться?)"
ok "триаж 5xx собран (502/503/504, Retry-After у 503)"

# Задание 03a: условный GET и 304
ETAGF=/tmp/api-lab/m08-etag.txt
[[ -s "$ETAGF" ]] || fail "нет файла $ETAGF — tasks/03-conditional-concurrency.md (часть ETag)"
grep -q "304" "$ETAGF" || fail "$ETAGF: нет статуса 304 (If-None-Match не сработал?)"
# Проверяем «вживую», что сервер реально отдаёт ETag и 304 на совпадение
LIVE_ETAG=$(curl -s -i "$API/api/v1/tickets/1" | grep -i '^ETag:' | tr -d '\r' | awk '{print $2}' || true)
[[ -n "$LIVE_ETAG" ]] || fail "сервер не отдаёт ETag на GET /tickets/1 — стенд устарел?"
CODE304=$(http_code -H "If-None-Match: $LIVE_ETAG" "$API/api/v1/tickets/1")
[[ "$CODE304" == "304" ]] || fail "If-None-Match с верным ETag дал $CODE304, ожидался 304"
ok "условный GET работает (ETag -> 304)"

# Задание 03b: optimistic locking и 412
CONC=/tmp/api-lab/m08-concurrency.txt
[[ -s "$CONC" ]] || fail "нет файла $CONC — tasks/03-conditional-concurrency.md (часть 412)"
grep -q "412" "$CONC" || fail "$CONC: нет статуса 412 (If-Match с устаревшим ETag)"
# Живая проверка: устаревший If-Match -> 412
CODE412=$(http_code -X PATCH -H 'If-Match: "stale-etag-value"' \
  -H 'Content-Type: application/json' -d '{"priority":"low"}' "$API/api/v1/tickets/1")
[[ "$CODE412" == "412" ]] || fail "PATCH с устаревшим If-Match дал $CODE412, ожидался 412"
ok "optimistic locking работает (If-Match -> 412)"

# Задание 04: асинхронный экспорт доведён до done (202 -> polling)
EXP=/tmp/api-lab/m08-export.json
require_valid_json_file "$EXP"
EST=$(jq -r '.status' "$EXP" 2>/dev/null || true)
[[ "$EST" == "done" ]] || fail "$EXP: status='$EST', ожидался 'done' (дождались ли готовности?)"
jq -e '.download_url' "$EXP" >/dev/null 2>&1 \
  || fail "$EXP: нет download_url — это не финальный (done) ответ статуса"
ok "асинхронный экспорт доведён до done (202 Accepted -> polling -> done)"

# Broken-сценарий: слепой диагноз 5xx совпал с фактом
ACTUAL_FILE=/tmp/api-lab/.m08-actual
DIAG_FILE=/tmp/api-lab/m08-5xx-diagnosis.txt
[[ -f "$ACTUAL_FILE" ]] || fail "не запускался broken/scenario-01/inject.sh"
[[ -f "$DIAG_FILE" ]] || fail "нет диагноза в $DIAG_FILE — broken/scenario-01"
ACTUAL=$(head -1 "$ACTUAL_FILE" | tr -d '[:space:]' || true)
DIAG=$(head -1 "$DIAG_FILE" | tr -d '[:space:]' || true)
[[ -n "$DIAG" && "$DIAG" == "$ACTUAL" ]] \
  || fail "слепой диагноз 5xx '$DIAG' не совпал с фактом '$ACTUAL'"
ok "слепая диагностика 5xx пройдена ($ACTUAL)"

ok "module 08 verified"
