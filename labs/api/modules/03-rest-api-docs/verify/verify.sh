#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
source "$ROOT_DIR/scripts/verify/helpers.sh"

need_bin curl
need_bin jq
require_api_up

# Практикум 2.2: ответы из документации
DOCS=/tmp/api-lab/m03-docs.txt
[[ -s "$DOCS" ]] || fail "нет файла $DOCS — практикум 2.2 (ответы из доки)"
grep -q "50" "$DOCS" || fail "$DOCS: нет ответа про максимум per_page (50)"
grep -q "201" "$DOCS" || fail "$DOCS: нет ответа про код успешного создания (201)"
grep -qi "title" "$DOCS" || fail "$DOCS: нет ответа про обязательное поле (title)"
ok "ответы по документации записаны в $DOCS"

# Задание 01: обход пагинации
IDS=/tmp/api-lab/m03-ids.txt
[[ -s "$IDS" ]] || fail "нет файла $IDS — задание tasks/01-pagination.md"
for i in 1 2 4 5 6 7; do   # 3 и 8 могли быть изменены/удалены другими модулями
  grep -qx "$i" "$IDS" || fail "$IDS: нет id=$i — собраны не все страницы?"
done
DUP=$(sort "$IDS" | uniq -d | head -1 || true)
[[ -z "$DUP" ]] || fail "$IDS: дубликат id=$DUP — страницы пересекаются?"
ok "пагинация обойдена полностью (без дублей)"

# Задание 02: жизненный цикл m03
ST=$(curl -s "$API/api/v1/tickets?q=m03" \
  | jq -r '.items[0] | "\(.status)/\(.priority)"' 2>/dev/null || true)
[[ "$ST" == "resolved/critical" ]] \
  || fail "тикет m03: ожидалось resolved/critical, получено '$ST' — tasks/02-lifecycle.md"
ok "жизненный цикл m03 пройден (critical -> in_progress -> resolved)"

# Broken-сценарий: заявка от мониторинга создана
CNT=$(curl -s -G "$API/api/v1/tickets" --data-urlencode 'q=Алерт: диск' \
  | jq -r '.total' 2>/dev/null || true)
[[ "$CNT" =~ ^[0-9]+$ && "$CNT" -ge 1 ]] \
  || fail "заявка 'Алерт: диск…' не найдена — broken/scenario-01 не починен"
ok "broken/scenario-01 починен (алерт мониторинга стал заявкой)"

ok "module 03 verified"
