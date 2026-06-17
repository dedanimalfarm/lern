#!/usr/bin/env bash
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Запусти через sudo/root"; exit 1; }

echo "Cleaning up Lab 3 (WireGuard) namespaces..."
ip netns del ns1 2>/dev/null || true
ip netns del ns2 2>/dev/null || true
echo "✅ Lab 3 cleanup complete."
