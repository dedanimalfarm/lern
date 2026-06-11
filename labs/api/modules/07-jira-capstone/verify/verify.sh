#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
source "$ROOT_DIR/scripts/verify/helpers.sh"

need_bin curl
need_bin jq

ENV_FILE="$HOME/.config/api-lab/jira.env"
[[ -f "$ENV_FILE" ]] || fail "нет $ENV_FILE — tasks/01-setup.md (и bash verify/prepare.sh)"
# shellcheck source=/dev/null
source "$ENV_FILE"
[[ -n "${JIRA_BASE_URL:-}" && -n "${JIRA_EMAIL:-}" && -n "${JIRA_API_TOKEN:-}" \
   && -n "${JIRA_PROJECT:-}" ]] || fail "jira.env заполнен не полностью"

jira() { curl -s --max-time 20 -u "$JIRA_EMAIL:$JIRA_API_TOKEN" "$@"; }

# Реквизиты валидны
ME=$(jira "$JIRA_BASE_URL/rest/api/3/myself" | jq -r '.accountId // empty' || true)
[[ -n "$ME" ]] || fail "myself не вернул accountId — реквизиты/связность"
ok "аутентификация в Jira работает"

# Поиск задач api-lab: пробуем актуальный /search/jql, при 404 — старый /search
search() {
  local jql="project = $JIRA_PROJECT AND labels = api-lab"
  local out
  out=$(jira -G "$JIRA_BASE_URL/rest/api/3/search/jql" \
    --data-urlencode "jql=$jql" --data-urlencode "fields=summary,status" || true)
  if ! echo "$out" | jq -e '.issues' >/dev/null 2>&1; then
    out=$(jira -G "$JIRA_BASE_URL/rest/api/3/search" \
      --data-urlencode "jql=$jql" --data-urlencode "fields=summary,status" || true)
  fi
  echo "$out"
}
RESULT=$(search)
TOTAL=$(echo "$RESULT" | jq '.issues | length' 2>/dev/null || true)
[[ "$TOTAL" =~ ^[0-9]+$ && "$TOTAL" -ge 2 ]] \
  || fail "задач с label=api-lab: '$TOTAL', нужно >= 2 — tasks/02-ticket-lifecycle.md"
ok "задачи api-lab созданы через API (найдено: $TOTAL)"

DONE=$(echo "$RESULT" | jq '[.issues[]
  | select(.fields.status.statusCategory.key == "done")] | length' 2>/dev/null || true)
[[ "$DONE" =~ ^[0-9]+$ && "$DONE" -ge 1 ]] \
  || fail "ни одна задача api-lab не доведена до Done (transitions!)"
ok "минимум одна задача проведена по workflow до Done"

# Postman-коллекция для Jira: валидна и без вшитых секретов
COL=/tmp/api-lab/m07-jira-collection.json
require_valid_json_file "$COL"
SCHEMA=$(jq -r '.info.schema // ""' "$COL" 2>/dev/null || true)
[[ "$SCHEMA" == *"v2.1.0"* ]] || fail "$COL: ожидался экспорт Collection v2.1"
if [[ -n "${JIRA_API_TOKEN:-}" ]] && grep -qF "$JIRA_API_TOKEN" "$COL"; then
  fail "$COL: в коллекции ВШИТ живой токен! Уберите в environment и переэкспортируйте"
fi
ok "Postman-коллекция Jira экспортирована и не содержит токена"

ok "module 07 verified"
