#!/usr/bin/env bash
# Исправленная интеграция мониторинг -> Helpdesk.
# Было три проблемы (все решались документацией):
#   1. 301: путь /api/v0/* выведен из эксплуатации -> /api/v1/*.
#      POST через redirect не понесёт тело корректно у многих клиентов,
#      поэтому чинится адрес, а не добавляется -L.
#   2. 422: словарь полей чужой системы: subject -> title,
#      severity -> priority (см. components/schemas/TicketCreate).
#   3. 422: status при создании задаёт сервер — поле убрано.
set -euo pipefail

API="http://localhost:8080"

curl -s -i -X POST "$API/api/v1/tickets" \
  -H 'Content-Type: application/json' \
  -d '{"title": "Алерт: диск заполнен на 95%", "priority": "critical"}'
echo
