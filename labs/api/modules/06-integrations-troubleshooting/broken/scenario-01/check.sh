#!/usr/bin/env bash
# Проверка слепого диагноза + уборка поломки.
set -euo pipefail

ACTUAL_FILE=/tmp/api-lab/.m06-actual
DIAG_FILE=/tmp/api-lab/m06-diagnosis.txt

[[ -f "$ACTUAL_FILE" ]] || { echo "[FAIL] сначала bash inject.sh" >&2; exit 1; }
[[ -f "$DIAG_FILE" ]] || { echo "[FAIL] запишите диагноз в $DIAG_FILE" >&2; exit 1; }

ACTUAL=$(head -1 "$ACTUAL_FILE" | tr -d '[:space:]')
DIAG=$(head -1 "$DIAG_FILE" | tr -d '[:space:]')

# выключаем поломку в любом случае — стенд не должен остаться сломанным
curl -s -X POST http://localhost:8080/api/v1/_lab/fault \
  -H 'Content-Type: application/json' -d '{"mode":"none"}' >/dev/null

if [[ "$DIAG" == "$ACTUAL" ]]; then
  echo "[OK] диагноз верный: $ACTUAL (поломка выключена)"
else
  echo "[FAIL] диагноз '$DIAG', а было '$ACTUAL'. Поломка выключена."
  echo "       Разбор различий: solutions/01-blind-diagnosis/README.md"
  echo "       Можно повторить: bash inject.sh (режим выпадет случайно)"
  exit 1
fi
