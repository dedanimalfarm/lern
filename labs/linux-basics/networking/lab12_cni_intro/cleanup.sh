#!/usr/bin/env bash
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Запусти через sudo/root"; exit 1; }

echo "Cleaning up Lab 12 (CNI Introduction) namespaces and bridge..."
ip netns del cni-ns 2>/dev/null || true
ip link del cni-br0 2>/dev/null || true
rm -f my-cni-config.json cni_output.json
echo "✅ Lab 12 cleanup complete."
