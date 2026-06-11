#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
source "$ROOT_DIR/scripts/verify/helpers.sh"

need_bin curl
need_bin jq
need_bin python3
require_api_up

# Задание 01: сводный отчёт
REPORT=/tmp/api-lab/m02-report.json
require_valid_json_file "$REPORT"
TOTAL=$(jq -r '.total' "$REPORT" 2>/dev/null || true)
[[ "$TOTAL" =~ ^[0-9]+$ ]] || fail "$REPORT: .total отсутствует или не число"
BS_TYPE=$(jq -r '.by_status | type' "$REPORT" 2>/dev/null || true)
[[ "$BS_TYPE" == "object" ]] || fail "$REPORT: .by_status должен быть объектом (got: $BS_TYPE)"
CT_TYPE=$(jq -r '.critical_titles | type' "$REPORT" 2>/dev/null || true)
[[ "$CT_TYPE" == "array" ]] || fail "$REPORT: .critical_titles должен быть массивом (got: $CT_TYPE)"
ok "сводный отчёт m02-report.json собран (total=$TOTAL)"

# Задание 02: TSV открытых тикетов
TSV=/tmp/api-lab/m02-open.tsv
[[ -s "$TSV" ]] || fail "нет (или пуст) файл $TSV — задание tasks/02-tsv.md"
BAD=$(awk -F'\t' 'NF!=3' "$TSV" | wc -l || true)
[[ "$BAD" == "0" ]] || fail "$TSV: есть строки не из 3 колонок (разделитель — табуляция!)"
ok "табличная выгрузка m02-open.tsv корректна ($(wc -l <"$TSV") строк)"

# Broken-сценарий: payload починен и заявка создана
PAYLOAD=/tmp/api-lab/m02-payload.json
require_valid_json_file "$PAYLOAD"
CNT=$(curl -s -G "$API/api/v1/tickets" --data-urlencode 'q=Импорт из CRM' \
  | jq -r '.total' 2>/dev/null || true)
[[ "$CNT" =~ ^[0-9]+$ && "$CNT" -ge 1 ]] \
  || fail "заявка 'Импорт из CRM…' не найдена — broken/scenario-01 не доведён до POST"
ok "broken/scenario-01 починен (payload валиден, заявка 'Импорт из CRM…' создана)"

ok "module 02 verified"
