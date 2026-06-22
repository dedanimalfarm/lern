#!/usr/bin/env bash
# Проверка решения лабы 06-advanced-tracing
set -uo pipefail

ok()   { printf "  [OK]   %s\n" "$1"; }
fail() { printf "  [FAIL] %s\n" "$1"; FAILED=1; }
FAILED=0

# 1. Проверяем, запущен ли ещё stuck_app.py
if pgrep -f 'stuck_app.py' >/dev/null 2>&1; then
  fail "Зависшее приложение stuck_app.py всё ещё выполняется в фоне (проблема не решена)"
else
  ok "Приложение stuck_app.py успешно прочитало конфигурационный файл и завершилось"
fi

# 2. Проверяем, что файл конфигурации был создан
if [ ! -f /tmp/missing_config.conf ]; then
  fail "Файл конфигурации /tmp/missing_config.conf не был создан"
else
  ok "Конфигурационный файл /tmp/missing_config.conf на месте"
fi

echo
if [ "$FAILED" -eq 0 ]; then
  echo "verify: ok"
  exit 0
else
  echo "Есть невыполненные условия."
  exit 1
fi
