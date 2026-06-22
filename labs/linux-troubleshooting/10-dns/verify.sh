#!/usr/bin/env bash
# Проверка решения лабы 10-dns
set -uo pipefail

ok()   { printf "  [OK]   %s\n" "$1"; }
fail() { printf "  [FAIL] %s\n" "$1"; FAILED=1; }
FAILED=0

# 1. Проверяем, что в /etc/hosts больше нет подложной записи
if grep -q '^192\.0\.2\.1[[:space:]]\+github\.com' /etc/hosts 2>/dev/null; then
  fail "В /etc/hosts всё ещё присутствует подмена для github.com на IP 192.0.2.1"
else
  ok "Подмена github.com в /etc/hosts удалена"
fi

# 2. Сбрасываем кеш resolved (чтобы убрать старую запись из кеша)
resolvectl flush-caches 2>/dev/null || true

# 3. Проверяем резолв через системные библиотеки
RESOLVED_IP=$(getent hosts github.com 2>/dev/null | awk '{print $1}' | head -n 1)
if [ "$RESOLVED_IP" = "192.0.2.1" ]; then
  fail "Системный резолвер всё ещё возвращает подложный IP 192.0.2.1 для github.com"
else
  ok "Системный резолвер возвращает корректный IP для github.com: ${RESOLVED_IP:-не определен}"
fi

echo
if [ "$FAILED" -eq 0 ]; then
  echo "verify: ok"
  exit 0
else
  echo "Есть невыполненные условия."
  exit 1
fi
