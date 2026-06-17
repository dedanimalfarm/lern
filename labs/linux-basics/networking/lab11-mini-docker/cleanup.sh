#!/usr/bin/env bash
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Запусти через sudo/root"; exit 1; }

echo "Cleaning up Lab 11 (Mini Docker) containers and bridge..."

# 1. Stop containers and delete namespaces
containers=$(ip netns list | awk '{print $1}')
for c in $containers; do
    PID_FILE="/tmp/mini-docker-$c.pid"
    if [ -f "$PID_FILE" ]; then
        kill $(cat "$PID_FILE" 2>/dev/null) 2>/dev/null || true
    fi
    rm -rf /tmp/mini-docker-$c*
    ip netns del "$c" 2>/dev/null || true
done

# 2. Delete bridge
ip link del docker-br0 2>/dev/null || true

# 3. Safely delete only mini-docker iptables rules
DEFAULT_IFACE=$(ip route show default | awk '/default/ {print $5}' | head -1) || true
if [ -n "$DEFAULT_IFACE" ]; then
    iptables -t nat -D POSTROUTING -s 10.11.0.0/24 -o "$DEFAULT_IFACE" -j MASQUERADE 2>/dev/null || true
fi

# Delete any NAT rules containing 10.11.0. subnet
if command -v iptables-save &>/dev/null; then
    iptables-save -t nat | grep "10.11.0." | sed 's/^-A //g' | while read -r rule; do
        iptables -t nat -D $rule 2>/dev/null || true
    done
    # Delete any NAT rules referencing port 8080 (our test port)
    iptables-save -t nat | grep "8080" | sed 's/^-A //g' | while read -r rule; do
        iptables -t nat -D $rule 2>/dev/null || true
    done
fi

rm -f /tmp/mini-docker-ip.txt
echo "✅ Lab 11 cleanup complete."
