#!/usr/bin/env bash
# Сброс окружения лабы 06-advanced-tracing
set -uo pipefail

echo "Остановка зависших процессов..."
pkill -9 -f 'stuck_app.py' 2>/dev/null || true

echo "Удаление временных файлов..."
rm -f /tmp/stuck_app.py /tmp/missing_config.conf 2>/dev/null || true

echo "Очистка завершена."
