#!/usr/bin/env bash
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Запусти через sudo/root"; exit 1; }

# Cleaning up Lab 7 (iptables/nftables) namespaces, bridge and rules...
# Kill lingering background test servers (ncat, haproxy) to release interfaces
pkill -f "ncat -l" || true
killall haproxy 2>/dev/null || true

for NS in web app db; do
    ip netns del $NS 2>/dev/null || true
done
ip link del br0 2>/dev/null || true
iptables -F || true
iptables -t nat -F || true
iptables -P INPUT ACCEPT || true
iptables -P FORWARD ACCEPT || true
nft flush ruleset 2>/dev/null || true
sysctl -w net.ipv4.ip_forward=0 >/dev/null 2>&1 || true
echo "✅ Lab 7 cleanup complete."

