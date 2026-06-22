#!/usr/bin/env bash
set -euo pipefail

echo "==> Очистка модуля 05: Observability — метрики"

# Stop docker containers if running
if [ -f ~/lab05/compose.yml ] || [ -f ~/lab05/docker-compose.yml ]; then
    echo "Останавливаем compose-стек..."
    (cd ~/lab05 && docker compose down -v || true)
else
    echo "Compose файл не найден, пробуем остановить по именам..."
    docker stop prometheus node-exporter cadvisor grafana myexp 2>/dev/null || true
    docker rm prometheus node-exporter cadvisor grafana myexp 2>/dev/null || true
fi

# Kill any python exporter
echo "Останавливаем python exporter..."
pkill -f "python3.*myexp.py" || true

# Remove directories and files
echo "Удаляем файлы лабы..."
rm -rf ~/lab05

echo "==> Очистка завершена!"
