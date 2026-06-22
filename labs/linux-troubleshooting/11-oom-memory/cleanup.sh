#!/usr/bin/env bash
# Очистка для лабы 11-oom-memory
set -uo pipefail

echo "Убиваем жадные процессы (stress-ng, python3 с bytearray)..."
killall stress-ng 2>/dev/null || true
pkill -f 'stress-ng.*--vm-keep' 2>/dev/null || true
pkill -f 'bytearray.*50.*1024.*1024' 2>/dev/null || true

sleep 1

# Проверяем, что память освобождена
MEM_AVAIL=$(awk '/MemAvailable/ {print $2}' /proc/meminfo)
echo "Доступная память после очистки: $((MEM_AVAIL / 1024)) МБ"

echo "Очистка завершена!"
