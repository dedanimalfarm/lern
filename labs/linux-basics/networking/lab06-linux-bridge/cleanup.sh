#!/usr/bin/env bash
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Запусти через sudo/root"; exit 1; }

echo "Cleaning up Lab 6 (Linux Bridge) namespaces and bridge..."

# 1. Delete namespaces
for NS in red blue green; do
    ip netns del "$NS" 2>/dev/null || true
    rm -rf "/etc/netns/$NS" 2>/dev/null || true
done

# 2. Delete bridge
ip link del br0 2>/dev/null || true

# 3. Safely delete iptables rules (only those created in the lab)
DEFAULT_IFACE=$(ip route show default | awk '/default/ {print $5}' | head -1) || true
if [ -n "$DEFAULT_IFACE" ]; then
    iptables -t nat -D POSTROUTING -s 10.0.0.0/24 -o "$DEFAULT_IFACE" -j MASQUERADE 2>/dev/null || true
    iptables -D FORWARD -i br0 -o "$DEFAULT_IFACE" -j ACCEPT 2>/dev/null || true
    iptables -D FORWARD -i "$DEFAULT_IFACE" -o br0 -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true
fi
iptables -t nat -D PREROUTING -p tcp --dport 8080 -j DNAT --to-destination 10.0.0.2:80 2>/dev/null || true
iptables -D FORWARD -p tcp -d 10.0.0.2 --dport 80 -j ACCEPT 2>/dev/null || true

echo "✅ Lab 6 cleanup complete."
