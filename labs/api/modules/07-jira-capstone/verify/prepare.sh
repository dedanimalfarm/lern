#!/usr/bin/env bash
# Модуль 07 работает с ВНЕШНИМ SaaS — prepare только проверяет готовность.
set -euo pipefail

ENV_FILE="$HOME/.config/api-lab/jira.env"
if [[ ! -f "$ENV_FILE" ]]; then
  cat >&2 <<'EOF'
[FAIL] нет ~/.config/api-lab/jira.env — выполните tasks/01-setup.md:
  1) бесплатный сайт: https://www.atlassian.com/software/jira/service-management/free
  2) API-токен: https://id.atlassian.com/manage-profile/security/api-tokens
  3) файл с JIRA_BASE_URL / JIRA_EMAIL / JIRA_API_TOKEN / JIRA_PROJECT (chmod 600)
EOF
  exit 1
fi

# shellcheck source=/dev/null
source "$ENV_FILE"
: "${JIRA_BASE_URL:?jira.env: нет JIRA_BASE_URL}"
: "${JIRA_EMAIL:?jira.env: нет JIRA_EMAIL}"
: "${JIRA_API_TOKEN:?jira.env: нет JIRA_API_TOKEN}"
: "${JIRA_PROJECT:?jira.env: нет JIRA_PROJECT}"

CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 \
  -u "$JIRA_EMAIL:$JIRA_API_TOKEN" "$JIRA_BASE_URL/rest/api/3/myself" || true)
[[ "$CODE" == "200" ]] || {
  echo "[FAIL] $JIRA_BASE_URL/rest/api/3/myself -> HTTP $CODE (ожидался 200)." >&2
  echo "       401 — проверьте email/токен; 000 — связность с интернетом." >&2
  exit 1
}
echo "[OK] module 07 prepared (Jira доступна, реквизиты валидны)"
