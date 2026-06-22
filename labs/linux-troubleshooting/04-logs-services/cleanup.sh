#!/usr/bin/env bash
# Сброс окружения лабы 04-logs-services
set -uo pipefail

echo "Остановка и удаление systemd-сервиса broken-app..."
systemctl stop broken-app 2>/dev/null || true
systemctl disable broken-app 2>/dev/null || true
rm -f /etc/systemd/system/broken-app.service

echo "Перезагрузка конфигурации systemd-демона..."
systemctl daemon-reload
systemctl reset-failed 2>/dev/null || true

echo "Удаление временных файлов..."
rm -f /tmp/magic_config.ini

echo "Очистка завершена."
