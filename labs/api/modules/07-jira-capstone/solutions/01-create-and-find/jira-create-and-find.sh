#!/usr/bin/env bash
# Исправленный скрипт. Было две поломки «эволюции API»:
#   1. 400 при создании: в /rest/api/3 поле description обязано быть
#      ADF-документом (Atlassian Document Format), а не строкой.
#   2. Поиск: /rest/api/3/search выведен из эксплуатации; актуальный
#      эндпоинт — /rest/api/3/search/jql.
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
      "description": {
        "type": "doc", "version": 1,
        "content": [{"type": "paragraph", "content": [
          {"type": "text", "text": "Создано автоматикой смены."}
        ]}]
      }
    }
  }' | jq '{id, key}'

echo "== ищем свои задачи =="
curl -s "${AUTH[@]}" -G "$JIRA_BASE_URL/rest/api/3/search/jql" \
  --data-urlencode "jql=project = $JIRA_PROJECT AND labels = api-lab" \
  --data-urlencode "fields=summary,status" \
  | jq '.issues[] | {key, summary: .fields.summary, status: .fields.status.name}'
