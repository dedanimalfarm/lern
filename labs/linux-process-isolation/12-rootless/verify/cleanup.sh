#!/usr/bin/env bash
# cleanup: user-ns эфемерны (умирают с процессом). Снимаем лишь временные файлы.
set -uo pipefail
rm -f /tmp/lpi-rootless-test /tmp/x /tmp/lpi-rl /tmp/lpi-c 2>/dev/null || true
echo "[OK] cleanup 12-rootless"
