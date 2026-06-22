#!/usr/bin/env bash
# Проверка решения лабы 04-logs-services
set -uo pipefail

ok()   { printf "  [OK]   %s\n" "$1"; }
fail() { printf "  [FAIL] %s\n" "$1"; FAILED=1; }
FAILED=0

# 1. Проверяем наличие конфигурационного файла
if [ ! -f /tmp/magic_config.ini ]; then
  fail "Конфигурационный файл /tmp/magic_config.ini не найден"
else
  ok "Конфигурационный файл /tmp/magic_config.ini на месте"
fi

# 2. Проверяем статус systemd сервиса broken-app
if ! systemctl is-active broken-app >/dev/null 2>&1; then
  fail "Сервис broken-app всё ещё не запущен или находится в состоянии сбоя (failed)"
else
  ok "Сервис broken-app успешно запущен и работает (active)"
fi

echo
if [ "$FAILED" -eq 0 ]; then
  echo "verify: ok"
  exit 0
else
  echo "Есть невыполненные условия."
  exit 1
fi
