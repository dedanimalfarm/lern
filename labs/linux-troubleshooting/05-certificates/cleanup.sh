#!/usr/bin/env bash
# Сброс окружения лабы 05-certificates
set -uo pipefail

echo "Удаление временных сертификатов..."
rm -rf /tmp/certs 2>/dev/null || true

echo "Очистка завершена."
