#!/usr/bin/env bash
# Исправленный скрипт создания заявки.
# Было три ошибки (каждая — свой статус-код):
#   1. 404: путь /api/v1/ticket  -> правильно /api/v1/tickets
#      (коллекции в REST именуются во множественном числе)
#   2. 415: POST с JSON-телом обязан объявлять формат:
#      -H 'Content-Type: application/json'
#   3. 400: JSON не признаёт одинарных кавычек — только двойные.
set -euo pipefail

API="http://localhost:8080"

curl -s -i -X POST "$API/api/v1/tickets" \
  -H 'Content-Type: application/json' \
  -d '{"title": "Заявка из скрипта", "priority": "high"}'
echo
