#!/usr/bin/env bash
# Сброс окружения лабы 02-disk-io
set -uo pipefail

echo "Остановка симуляционных процессов..."
pkill -9 -f 'tail -f /tmp/hidden_leak.dat' 2>/dev/null || true

echo "Удаление временных файлов..."
rm -f /tmp/hidden_leak.dat 2>/dev/null || true

echo "Очистка завершена."
