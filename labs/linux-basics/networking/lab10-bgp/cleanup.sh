#!/usr/bin/env bash
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Запусти через sudo/root"; exit 1; }

echo "Cleaning up Lab 10 (BGP) processes and namespaces..."
for i in r1 r2 r3; do
    ip netns del $i 2>/dev/null || true
    PID_FILE="/tmp/bird-$i.pid"
    if [ -f "$PID_FILE" ]; then
        kill $(cat "$PID_FILE" 2>/dev/null) 2>/dev/null || true
        rm -f "$PID_FILE"
    fi
    rm -f "/tmp/bird-$i.ctl" "/tmp/bird-$i.conf"
done
echo "✅ Lab 10 cleanup complete."
