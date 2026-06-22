#!/usr/bin/env bash
# Очистка для лабы 10-dns
set -uo pipefail

echo "Удаляем подмену github.com из /etc/hosts..."
sudo sed -i '/192\.0\.2\.1[[:space:]]\+github\.com/d' /etc/hosts 2>/dev/null || true

# Сбросим кеш systemd-resolved, если он есть
sudo resolvectl flush-caches 2>/dev/null || true

echo "Очистка завершена!"
