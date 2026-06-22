#!/usr/bin/env bash
# Проверка решения лабы 02-disk-io
set -uo pipefail

ok()   { printf "  [OK]   %s\n" "$1"; }
fail() { printf "  [FAIL] %s\n" "$1"; FAILED=1; }
FAILED=0

# 1. Проверяем, запущен ли симуляционный процесс tail, удерживающий файл
if pgrep -f 'tail -f /tmp/hidden_leak.dat' >/dev/null 2>&1; then
  fail "Симуляционный процесс tail всё ещё удерживает удаленный файл /tmp/hidden_leak.dat"
else
  ok "Процесс, удерживающий скрытую утечку диска, остановлен"
fi

# 2. Проверяем, что в lsof +L1 нет удаленного файла hidden_leak.dat
if command -v lsof >/dev/null 2>&1; then
  if lsof +L1 2>/dev/null | grep -q 'hidden_leak.dat'; then
    fail "Файл /tmp/hidden_leak.dat всё ещё удерживается открытым в файловой системе"
  else
    ok "Удаленный файл больше не занимает скрытое место на диске"
  fi
fi

echo
if [ "$FAILED" -eq 0 ]; then
  echo "verify: ok"
  exit 0
else
  echo "Есть невыполненные условия."
  exit 1
fi
