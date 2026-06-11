#!/usr/bin/env bash
# Скрипт «из вики 2023 года»: создать задачу и найти свои задачи в Jira.
# Жалоба: «работал годами, после переезда на новый сайт — сплошные ошибки».
# Обе проблемы описаны в актуальной документации Atlassian (Часть 3 README).
# Требует: source ~/.config/api-lab/jira.env
set -euo pipefail

: "${JIRA_BASE_URL:?сначала: source ~/.config/api-lab/jira.env}"
AUTH=(-u "$JIRA_EMAIL:$JIRA_API_TOKEN")

echo "== создаём задачу =="
curl -s "${AUTH[@]}" -X POST "$JIRA_BASE_URL/rest/api/3/issue" \
  -H 'Content-Type: application/json' \
  -d '{
    "fields": {
      "project": {"key": "'"$JIRA_PROJECT"'"},
      "issuetype": {"name": "Task"},
      "summary": "Заявка из скрипта (api-lab)",
      "labels": ["api-lab"],
      "description": "Создано автоматикой смены."
    }
  }'
echo

echo "== ищем свои задачи =="
curl -s "${AUTH[@]}" -G "$JIRA_BASE_URL/rest/api/3/search" \
  --data-urlencode "jql=project = $JIRA_PROJECT AND labels = api-lab" \
  --data-urlencode "fields=summary,status"
echo
