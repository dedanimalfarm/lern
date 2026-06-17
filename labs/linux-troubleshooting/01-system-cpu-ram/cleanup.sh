#!/usr/bin/env bash
# Сброс окружения лабы 01-system-cpu-ram
set -uo pipefail

echo "Остановка симуляционных процессов..."
# Убиваем только специфичную нагрузку, запущенную в рамках лабы
pkill -9 -f 'stress-ng --cpu 2 --vm 1 --vm-bytes 500M' 2>/dev/null || true

echo "Очистка завершена."
