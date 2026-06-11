#!/usr/bin/env bash
# Скрипт «из корпоративной вики»: заводит заявку в Helpdesk.
# Жалоба пользователя: «запускаю — заявка не создаётся».
# НЕ подглядывайте в solutions/: чините по ответам сервера.
set -euo pipefail

API="http://localhost:8080"

curl -s -X POST "$API/api/v1/ticket" \
  -d "{'title': 'Заявка из скрипта', 'priority': 'high'}"
echo
