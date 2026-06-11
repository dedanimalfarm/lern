#!/usr/bin/env bash
# Отчёт смены по проекту Jira: количество задач по статусам + список «в работе».
# Всё — одним JQL-запросом и jq-обработкой (рецепты модуля 02).
# Требует: source ~/.config/api-lab/jira.env
set -euo pipefail

: "${JIRA_BASE_URL:?сначала: source ~/.config/api-lab/jira.env}"
AUTH=(-u "$JIRA_EMAIL:$JIRA_API_TOKEN")

DATA=$(curl -s "${AUTH[@]}" -G "$JIRA_BASE_URL/rest/api/3/search/jql" \
  --data-urlencode "jql=project = $JIRA_PROJECT" \
  --data-urlencode "fields=summary,status" \
  --data-urlencode "maxResults=100")

echo "=== Отчёт смены: проект $JIRA_PROJECT ($(date -u +%Y-%m-%dT%H:%M:%SZ)) ==="
echo "По статусам:"
echo "$DATA" | jq -r '.issues | group_by(.fields.status.name)
  | map("  \(.[0].fields.status.name)\t\(length)") | .[]'

echo "В работе:"
echo "$DATA" | jq -r '.issues[]
  | select(.fields.status.statusCategory.key == "indeterminate")
  | "  \(.key)\t\(.fields.summary)"'
