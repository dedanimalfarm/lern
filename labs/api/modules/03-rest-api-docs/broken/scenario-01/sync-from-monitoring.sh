#!/usr/bin/env bash
# Интеграция: алерт мониторинга -> заявка в Helpdesk.
# Жалоба: «после миграции Helpdesk заявки по алертам не заводятся».
# Все три проблемы решаются чтением docs/openapi.yaml.
set -euo pipefail

API="http://localhost:8080"

curl -s -i -X POST "$API/api/v0/tickets" \
  -H 'Content-Type: application/json' \
  -d '{"subject": "Алерт: диск заполнен на 95%", "severity": "critical", "status": "open"}'
echo
