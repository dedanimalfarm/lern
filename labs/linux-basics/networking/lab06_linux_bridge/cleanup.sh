#!/usr/bin/env bash
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Запусти через sudo/root"; exit 1; }

echo "Cleaning up Lab 6 (Linux Bridge) namespaces and bridge..."
for NS in red blue green; do
    ip netns del $NS 2>/dev/null || true
done
ip link del br0 2>/dev/null || true
echo "✅ Lab 6 cleanup complete."
