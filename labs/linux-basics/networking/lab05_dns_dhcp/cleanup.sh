#!/usr/bin/env bash
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Запусти через sudo/root"; exit 1; }

echo "Cleaning up Lab 5 (DNS & DHCP) processes and namespaces..."
ip netns del server 2>/dev/null || true
ip netns del client 2>/dev/null || true
killall dnsmasq 2>/dev/null || true
rm -f /tmp/udhcpc.script
echo "✅ Lab 5 cleanup complete."
