#!/usr/bin/env bash
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Запусти через sudo/root"; exit 1; }

echo "Cleaning up Lab 9 (Traffic Control) namespaces and qdiscs..."
ip netns exec server tc qdisc del dev veth-srv root 2>/dev/null || true
ip netns del client 2>/dev/null || true
ip netns del server 2>/dev/null || true
echo "✅ Lab 9 cleanup complete."
