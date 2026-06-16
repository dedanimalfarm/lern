#!/bin/bash
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Запусти через sudo/root"; exit 1; }

echo "Verifying Lab 5 (DNS & DHCP / Dnsmasq)..."

# 1. Check if namespaces exist
if ! ip netns list | grep -q "server" || ! ip netns list | grep -q "client"; then
    echo "[FAIL] Namespace server or client does not exist."
    exit 1
fi

# 2. Check if dnsmasq is running in server namespace
if ! ip netns exec server pgrep dnsmasq >/dev/null 2>&1; then
    echo "[FAIL] Dnsmasq is not running inside 'server' namespace."
    exit 1
fi
echo "  [OK] Namespaces and Dnsmasq server are running."

# 3. Check client IP
client_ip=$(ip netns exec client ip -4 addr show veth-cli | grep -oP '(?<=inet\s)\d+(\.\d+){3}' || true)
if [ -z "$client_ip" ]; then
    echo "  Client has no IP. Requesting DHCP lease..."
    ip netns exec client busybox udhcpc -i veth-cli -s /tmp/udhcpc.script -n -q >/dev/null 2>&1 || true
    client_ip=$(ip netns exec client ip -4 addr show veth-cli | grep -oP '(?<=inet\s)\d+(\.\d+){3}' || true)
fi

if [ -z "$client_ip" ]; then
    echo "[FAIL] Client failed to obtain DHCP lease."
    exit 1
fi
echo "  [OK] Client has IP: $client_ip"

# 4. Check DNS resolution
resolved_db=$(ip netns exec client dig +short @10.0.0.1 db.internal.company | tail -n1)
if [ "$resolved_db" = "10.0.0.100" ]; then
    echo "  [OK] DNS resolved db.internal.company -> $resolved_db"
    echo "✅ Lab 5 Verification Successful!"
    exit 0
else
    echo "[FAIL] DNS resolution failed. db.internal.company resolved to '$resolved_db' instead of '10.0.0.100'."
    exit 1
fi
