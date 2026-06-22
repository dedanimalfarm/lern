#!/usr/bin/env bash
# Проверка решения лабы 07-network-traffic
set -uo pipefail

ok()   { printf "  [OK]   %s\n" "$1"; }
fail() { printf "  [FAIL] %s\n" "$1"; FAILED=1; }
FAILED=0

# 1. Проверяем, что фоновый curl-генератор остановлен
if pgrep -f 'curl -s --connect-timeout 1 http://93.184.216.34' >/dev/null 2>&1; then
  fail "Фоновый генератор запросов к подозрительному IP всё ещё запущен (проблема не решена)"
else
  ok "Генератор подозрительного HTTP-трафика остановлен"
fi

# 2. Проверяем наличие файла с правильным IP-адресом
if [ ! -f /tmp/suspicious_ip.txt ]; then
  fail "Файл с решением /tmp/suspicious_ip.txt не найден"
else
  IP_CONTENT=$(cat /tmp/suspicious_ip.txt | tr -d '[:space:]')
  if [ "$IP_CONTENT" = "93.184.216.34" ]; then
    ok "В файле указан правильный подозрительный IP-адрес: $IP_CONTENT"
  else
    fail "В файле указан неверный IP-адрес: '$IP_CONTENT' (ожидалось '93.184.216.34')"
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
