#!/usr/bin/env bash
# Проверяет слепой диагноз 5xx и снимает поломку.
set -euo pipefail

ACTUAL_FILE=/tmp/api-lab/.m08-actual
DIAG_FILE=/tmp/api-lab/m08-5xx-diagnosis.txt

[[ -f "$ACTUAL_FILE" ]] || { echo "[FAIL] не запускался inject.sh" >&2; exit 1; }
[[ -f "$DIAG_FILE" ]] || { echo "[FAIL] нет $DIAG_FILE с вашим диагнозом" >&2; exit 1; }

ACTUAL=$(head -1 "$ACTUAL_FILE" | tr -d '[:space:]')
DIAG=$(head -1 "$DIAG_FILE" | tr -d '[:space:]')

# Поломку снимаем в любом случае — чтобы стенд не остался сломанным
curl -s -X POST http://localhost:8080/api/v1/_lab/fault \
  -H 'Content-Type: application/json' -d '{"mode":"none"}' >/dev/null 2>&1 || true

if [[ "$DIAG" == "$ACTUAL" ]]; then
  echo "[OK] диагноз верный: $ACTUAL (поломка выключена)"
else
  echo "[FAIL] ваш диагноз '$DIAG', а на деле было '$ACTUAL' (поломка выключена)" >&2
  exit 1
fi
