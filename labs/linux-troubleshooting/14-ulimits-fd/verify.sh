#!/usr/bin/env bash
# Проверка решения лабы 14-ulimits-fd
set -uo pipefail

ok()   { printf "  [OK]   %s\n" "$1"; }
fail() { printf "  [FAIL] %s\n" "$1"; FAILED=1; }
FAILED=0

# 1. Проверяем, что мягкий лимит fd в текущей сессии достаточен (>= 5000)
SOFT_LIMIT=$(ulimit -Sn)
if [ "$SOFT_LIMIT" = "unlimited" ] || [ "$SOFT_LIMIT" -ge 5000 ]; then
  ok "Мягкий лимит файловых дескрипторов достаточен: $SOFT_LIMIT (нужно >= 5000)"
else
  fail "Мягкий лимит слишком мал: $SOFT_LIMIT (нужно >= 5000). Подними: ulimit -n 8192"
fi

# 2. Запускаем simulate.sh с KEEP_LIMIT=1 и проверяем, что он завершается успешно
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if KEEP_LIMIT=1 bash "$SCRIPT_DIR/simulate.sh" 2>&1 | grep -q "Открыто 5000 файлов"; then
  ok "Тест с KEEP_LIMIT=1 прошёл успешно — удалось открыть 5000 файлов"
else
  fail "Тест с KEEP_LIMIT=1 завершился неудачно — приложение всё ещё падает с 'Too many open files'"
fi

echo
if [ "$FAILED" -eq 0 ]; then
  echo "verify: ok"
  exit 0
else
  echo "Есть невыполненные условия."
  exit 1
fi
