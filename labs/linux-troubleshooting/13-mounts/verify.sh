#!/usr/bin/env bash
# Проверка решения лабы 13-mounts
set -uo pipefail

ok()   { printf "  [OK]   %s\n" "$1"; }
fail() { printf "  [FAIL] %s\n" "$1"; FAILED=1; }
FAILED=0

MP=/mnt/lab-mount
IMG=/tmp/lab-mount.img

# 1. Проверяем, что точка монтирования размонтирована
if findmnt --target "$MP" >/dev/null 2>&1; then
  fail "Точка монтирования $MP всё ещё смонтирована (target is busy или не размонтирована)"
else
  ok "Точка монтирования $MP успешно размонтирована"
fi

# 2. Проверяем, что loop-устройства, привязанные к образу, освобождены
if [ -f "$IMG" ]; then
  LOOPS=$(losetup -j "$IMG" 2>/dev/null | cut -d: -f1)
  if [ -n "$LOOPS" ]; then
    fail "Файл-образ $IMG всё ещё привязан к loop-устройствам: $LOOPS"
  else
    ok "Loop-устройства образа $IMG освобождены (файл образа ещё есть — cleanup.sh уберёт его)"
  fi
else
  ok "Файл-образ $IMG удалён и loop-устройство освобождено"
fi

# 3. Проверяем, что процессы внутри /mnt/lab-mount убиты
if pgrep -f "sleep 9999" >/dev/null 2>&1 || pgrep -f "tail -f $MP" >/dev/null 2>&1; then
  fail "Процессы-«держатели» точки монтирования всё ещё запущены (sleep 9999 или tail -f)"
else
  ok "Процессы-«держатели» точки монтирования остановлены"
fi

echo
if [ "$FAILED" -eq 0 ]; then
  echo "verify: ok"
  exit 0
else
  echo "Есть невыполненные условия."
  exit 1
fi
