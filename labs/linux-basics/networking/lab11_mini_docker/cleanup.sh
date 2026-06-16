#!/usr/bin/env bash
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Запусти через sudo/root"; exit 1; }

echo "Cleaning up Lab 11 (Mini Docker) containers and bridge..."
containers=$(ip netns list | awk '{print $1}')
for c in $containers; do
    PID_FILE="/tmp/mini-docker-$c.pid"
    if [ -f "$PID_FILE" ]; then
        kill $(cat "$PID_FILE" 2>/dev/null) 2>/dev/null || true
    fi
    rm -rf /tmp/mini-docker-$c*
    ip netns del $c 2>/dev/null || true
done
ip link del docker-br0 2>/dev/null || true
iptables -t nat -F || true
echo "✅ Lab 11 cleanup complete."
