#!/usr/bin/env bash
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Запусти через sudo/root"; exit 1; }

echo "Cleaning up Lab 2 (Load Balancer) processes..."
pkill -f 'http.server 808[123]' 2>/dev/null || true
killall haproxy 2>/dev/null || true
echo "✅ Lab 2 cleanup complete."
