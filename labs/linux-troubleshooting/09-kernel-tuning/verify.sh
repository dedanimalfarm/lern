#!/usr/bin/env bash
# Проверка решения лабы 09-kernel-tuning
set -uo pipefail

ok()   { printf "  [OK]   %s\n" "$1"; }
fail() { printf "  [FAIL] %s\n" "$1"; FAILED=1; }
FAILED=0

# 1. Проверяем текущее значение лимита ядра
CURRENT_LIMIT=$(sysctl -n fs.inotify.max_user_watches)
if [ "$CURRENT_LIMIT" -ge 15000 ]; then
  ok "Текущий лимит inotify watches достаточен для приложения: $CURRENT_LIMIT (требовалось >= 15000)"
else
  fail "Текущий лимит inotify watches слишком мал: $CURRENT_LIMIT (ожидалось >= 15000, рекомендовано 524288)"
fi

# 2. Проверяем персистентность настройки в sysctl конфигурациях
PERSISTENT_FOUND=0
if grep -r -q "^[[:space:]]*fs.inotify.max_user_watches" /etc/sysctl.conf /etc/sysctl.d/ 2>/dev/null; then
  # Найдена строка, проверим значение в найденных файлах
  CONF_VAL=$(grep -r "^[[:space:]]*fs.inotify.max_user_watches" /etc/sysctl.conf /etc/sysctl.d/ 2>/dev/null | awk -F'=' '{print $2}' | tr -d '[:space:]' | head -n 1)
  if [ -n "$CONF_VAL" ] && [ "$CONF_VAL" -ge 15000 ]; then
    PERSISTENT_FOUND=1
    ok "Параметр fs.inotify.max_user_watches настроен персистентно: значение в конфиге = $CONF_VAL"
  fi
fi

if [ "$PERSISTENT_FOUND" -eq 0 ]; then
  fail "Параметр fs.inotify.max_user_watches не найден в конфигурационных файлах sysctl (/etc/sysctl.conf или /etc/sysctl.d/*.conf) с нужным значением"
fi

echo
if [ "$FAILED" -eq 0 ]; then
  echo "verify: ok"
  exit 0
else
  echo "Есть невыполненные условия."
  exit 1
fi
