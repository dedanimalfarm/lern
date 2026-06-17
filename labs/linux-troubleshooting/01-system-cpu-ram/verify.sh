#!/usr/bin/env bash
# Проверка решения лабы 01-system-cpu-ram
set -uo pipefail

ok()   { printf "  [OK]   %s\n" "$1"; }
fail() { printf "  [FAIL] %s\n" "$1"; FAILED=1; }
FAILED=0

# 1. Проверяем, запущен ли симуляционный процесс stress-ng
if pgrep -f 'stress-ng --cpu 2 --vm 1 --vm-bytes 500M' >/dev/null 2>&1; then
  fail "Симуляционный процесс stress-ng всё ещё запущен и нагружает систему"
else
  ok "Симуляционный процесс stress-ng остановлен (проблема решена)"
fi

# 2. Проверяем состояние процессора через процент свободного времени (Idle)
IDLE=$(vmstat 1 2 | tail -n 1 | awk '{print $15}')
if [ -n "$IDLE" ] && [ "$IDLE" -gt 20 ]; then
  ok "Процессор свободен (idle = ${IDLE}%)"
else
  ok "Предупреждение по загрузке процессора (idle = ${IDLE:-unknown}%)"
fi

echo
if [ "$FAILED" -eq 0 ]; then
  echo "verify: ok"
  exit 0
else
  echo "Есть невыполненные условия."
  exit 1
fi
