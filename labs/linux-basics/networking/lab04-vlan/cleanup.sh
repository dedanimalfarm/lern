#!/usr/bin/env bash
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Запусти через sudo/root"; exit 1; }

echo "Cleaning up Lab 4 (VLAN) namespaces and bridge..."
ip netns del host1 2>/dev/null || true
ip netns del host2 2>/dev/null || true
ip netns del router 2>/dev/null || true
ip link del br0 2>/dev/null || true
echo "✅ Lab 4 cleanup complete."
