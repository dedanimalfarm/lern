#!/usr/bin/env bash
# Проверка решения лабы 03-networking
set -uo pipefail

ok()   { printf "  [OK]   %s\n" "$1"; }
fail() { printf "  [FAIL] %s\n" "$1"; FAILED=1; }
FAILED=0

# 1. Проверяем наличие блокирующего правила в iptables
if iptables -S INPUT 2>/dev/null | grep -q -- '-dport 8888 -j DROP'; then
  fail "Блокирующее правило для порта 8888 всё ещё присутствует в iptables"
else
  ok "Блокирующее правило в iptables отсутствует"
fi

# 2. Проверяем доступность порта 8888 (если сервер запущен)
if pgrep -f 'python3 -m http.server 8888' >/dev/null 2>&1; then
  if curl -s --connect-timeout 2 http://127.0.0.1:8888 >/dev/null 2>&1; then
    ok "Веб-сервер на порту 8888 успешно отвечает на запросы"
  else
    fail "Веб-сервер запущен, но порт 8888 всё ещё недоступен (проблема не решена)"
  fi
else
  ok "Веб-сервер не запущен, но блокирующее правило iptables снято (проблема решена)"
fi

echo
if [ "$FAILED" -eq 0 ]; then
  echo "verify: ok"
  exit 0
else
  echo "Есть невыполненные условия."
  exit 1
fi
