#!/usr/bin/env bash
# Сброс окружения лабы 03-networking
set -uo pipefail

echo "Остановка симуляционных процессов..."
pkill -9 -f 'python3 -m http.server 8888' 2>/dev/null || true

echo "Очистка правил iptables..."
while iptables -D INPUT -p tcp --dport 8888 -j DROP 2>/dev/null; do
  true
done

echo "Очистка завершена."
