#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
source "$ROOT_DIR/scripts/verify/helpers.sh"

need_bin curl
need_bin jq
require_api_up

# Конфигурация стенда: вебхуки включены, sink жив, поломка убрана
require_jq '.webhook_url' "http://127.0.0.1:9100/hook" "$API/api/v1/_lab/state"
require_http 200 "$SINK/health"
require_jq '.fault' "none" "$API/api/v1/_lab/state"
ok "стенд с вебхуками, sink жив, fault=none (за собой убрано)"

# Задание 01: событие ticket.created с тикетом m06 доставлено
DELIVERED=$(curl -s "$SINK/received" | jq '[.deliveries[].payload
  | select(.event=="ticket.created")
  | select(.ticket.title | test("m06"))] | length' 2>/dev/null || true)
[[ "$DELIVERED" =~ ^[0-9]+$ && "$DELIVERED" -ge 1 ]] \
  || fail "в sink нет ticket.created с тикетом m06 — tasks/01-webhook.md"
ok "вебхук ticket.created (тикет m06) доставлен в sink"

# Задание 02: идемпотентность — ровно один тикет idem-m06
IDEM=$(curl -s "$API/api/v1/tickets?q=idem-m06" | jq -r '.total' 2>/dev/null || true)
[[ "$IDEM" == "1" ]] \
  || fail "тикетов idem-m06: '$IDEM', ожидался ровно 1 (два POST с одним Idempotency-Key)"
ok "идемпотентность отработана (idem-m06 ровно один)"

# Слепая диагностика: диагноз совпал с фактом
ACTUAL_FILE=/tmp/api-lab/.m06-actual
DIAG_FILE=/tmp/api-lab/m06-diagnosis.txt
[[ -f "$ACTUAL_FILE" ]] || fail "не запускался broken/scenario-01/inject.sh"
[[ -f "$DIAG_FILE" ]] || fail "нет диагноза в $DIAG_FILE — broken/scenario-01"
ACTUAL=$(head -1 "$ACTUAL_FILE" | tr -d '[:space:]' || true)
DIAG=$(head -1 "$DIAG_FILE" | tr -d '[:space:]' || true)
[[ -n "$DIAG" && "$DIAG" == "$ACTUAL" ]] \
  || fail "слепой диагноз '$DIAG' не совпал с фактом '$ACTUAL'"
ok "слепая диагностика пройдена ($ACTUAL)"

# Эскалация по шаблону
ESC=/tmp/api-lab/m06-escalation.md
[[ -s "$ESC" ]] || fail "нет файла $ESC — tasks/03-escalation.md"
for sect in "Симптом" "Воспроизведение" "Ожидаемо" "проверено" "Workaround"; do
  grep -qi "^## .*$sect" "$ESC" || fail "$ESC: нет раздела '## …$sect…'"
done
grep -q "curl" "$ESC" || fail "$ESC: в воспроизведении должна быть точная команда (curl)"
ok "эскалация написана по шаблону (5 разделов, команды приложены)"

ok "module 06 verified"
