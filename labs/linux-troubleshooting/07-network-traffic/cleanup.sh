#!/usr/bin/env bash
# Сброс окружения лабы 07-network-traffic
set -uo pipefail

echo "Остановка генератора HTTP-трафика..."
pkill -9 -f 'curl -s --connect-timeout 1 http://93.184.216.34' 2>/dev/null || true

echo "Удаление временных файлов..."
rm -f /tmp/suspicious_ip.txt 2>/dev/null || true

echo "Очистка завершена."
