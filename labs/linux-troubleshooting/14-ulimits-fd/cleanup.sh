#!/usr/bin/env bash
# Очистка для лабы 14-ulimits-fd
set -uo pipefail

echo "Удаляем временные файлы /tmp/open_many_*.tmp..."
rm -f /tmp/open_many_*.tmp

echo "Убиваем зависшие python3-процессы (если есть)..."
pkill -f 'open_many' 2>/dev/null || true

echo "Очистка завершена!"
echo "Примечание: лимит ulimit -n применяется только к текущей сессии"
echo "и сбросится автоматически при закрытии терминала."
