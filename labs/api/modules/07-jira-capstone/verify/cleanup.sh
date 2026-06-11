#!/usr/bin/env bash
# Внешний SaaS: ничего не удаляем автоматически.
set -euo pipefail

rm -f /tmp/api-lab/m07-jira-collection.json
cat <<'EOF'
[OK] module 07 cleaned (локальные артефакты)
Облачный стенд остаётся вам для портфолио. Если он больше не нужен:
  - задачи api-lab можно удалить через API или UI;
  - API-токен отзывается на id.atlassian.com (Security -> API tokens);
  - сайт удаляется в admin.atlassian.com.
EOF
