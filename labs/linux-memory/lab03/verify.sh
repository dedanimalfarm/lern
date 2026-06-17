#!/usr/bin/env bash
# Проверка усвоенных навыков лабы "Transparent Hugepages (THP) и СУБД".
set -uo pipefail

ok()   { printf "  [OK]   %s\n" "$1"; }
fail() { printf "  [FAIL] %s\n" "$1"; FAILED=1; }
FAILED=0

ROOT=0; [ "$(id -u)" -eq 0 ] && ROOT=1

# 1. Проверка существования файлов THP
if [ -f /sys/kernel/mm/transparent_hugepage/enabled ] && [ -f /sys/kernel/mm/transparent_hugepage/defrag ]; then
  ok "Файлы управления Transparent Hugepages найдены"
else
  fail "Ядро не поддерживает Transparent Hugepages (файлы не найдены)"
fi

# 2. Проверка доступности статуса THP
ACTIVE_THP=$(grep -oP '\[\K[^\]]+' /sys/kernel/mm/transparent_hugepage/enabled)
if [ -n "$ACTIVE_THP" ]; then
  ok "Текущий статус THP успешно определен: $ACTIVE_THP"
else
  fail "Не удалось определить текущий статус THP"
fi

# 3. Проверка присутствия AnonHugePages в /proc/meminfo
if grep -q "AnonHugePages:" /proc/meminfo; then
  ok "Метрика AnonHugePages присутствует в /proc/meminfo"
else
  fail "Метрика AnonHugePages не найдена в /proc/meminfo"
fi

# 4. Проверка изменения статуса на never
if [ "$ROOT" -eq 1 ]; then
  ORIG_ENABLED=$(grep -oP '\[\K[^\]]+' /sys/kernel/mm/transparent_hugepage/enabled)
  echo "never" > /sys/kernel/mm/transparent_hugepage/enabled
  NEW_ENABLED=$(grep -oP '\[\K[^\]]+' /sys/kernel/mm/transparent_hugepage/enabled)
  if [ "$NEW_ENABLED" = "never" ]; then
    ok "Отключение THP (запись 'never' в enabled) работает корректно"
  else
    fail "Не удалось отключить THP (запись 'never' не изменила статус)"
  fi
  # Восстанавливаем оригинальный статус
  echo "$ORIG_ENABLED" > /sys/kernel/mm/transparent_hugepage/enabled
else
  ok "Пропуск проверки записи (не root, нужен sudo)"
fi

echo
if [ "$FAILED" -eq 0 ]; then
  echo "verify: ok"
  exit 0
else
  echo "Есть проваленные проверки."
  exit 1
fi
