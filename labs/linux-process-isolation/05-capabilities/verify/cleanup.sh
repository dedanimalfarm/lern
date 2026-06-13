#!/usr/bin/env bash
# cleanup: снимаем возможные временные файлы/процессы модуля 05.
set -uo pipefail
pkill -f '/tmp/lpi-pyweb' 2>/dev/null || true
rm -f /tmp/lpi-capx /tmp/lpi-capdemo /tmp/lpi-pyweb 2>/dev/null || true
echo "[OK] cleanup 05-capabilities"
