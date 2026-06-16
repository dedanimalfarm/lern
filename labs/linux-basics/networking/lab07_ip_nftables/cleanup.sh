#!/usr/bin/env bash
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Запусти через sudo/root"; exit 1; }

echo "Cleaning up Lab 7 (iptables/nftables) namespaces, bridge and rules..."
for NS in web app db; do
    ip netns del $NS 2>/dev/null || true
done
ip link del br0 2>/dev/null || true
iptables -F || true
iptables -t nat -F || true
nft flush ruleset 2>/dev/null || true
echo "✅ Lab 7 cleanup complete."
