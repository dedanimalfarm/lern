#!/usr/bin/env bash
# Проверка решения лабы 11-oom-memory
set -uo pipefail

ok()   { printf "  [OK]   %s\n" "$1"; }
fail() { printf "  [FAIL] %s\n" "$1"; FAILED=1; }
FAILED=0

# 1. Проверяем, что жадный процесс stress-ng / python больше не запущен
if pgrep -f 'stress-ng.*--vm-keep' >/dev/null 2>&1; then
  fail "Процесс stress-ng всё ещё запущен и потребляет память"
else
  ok "Жадный процесс stress-ng остановлен"
fi

if pgrep -f 'open_many\|bytearray.*1024.*1024' >/dev/null 2>&1; then
  fail "Жадный Python-процесс всё ещё запущен"
else
  ok "Жадный Python-процесс не запущен"
fi

# 2. Проверяем наличие OOM-записи в кольцевом буфере ядра
if dmesg | grep -qiE 'oom.kill|out of memory|killed process'; then
  ok "В dmesg присутствует запись об OOM Kill — факт убийства зафиксирован ядром"
else
  fail "В dmesg не найдено записи об OOM Kill. Возможно, OOM ещё не произошёл или буфер был очищен"
fi

echo
if [ "$FAILED" -eq 0 ]; then
  echo "verify: ok"
  exit 0
else
  echo "Есть невыполненные условия."
  exit 1
fi
