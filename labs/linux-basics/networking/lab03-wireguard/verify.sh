#!/bin/bash
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Запусти через sudo/root"; exit 1; }

echo "Verifying Lab 3 (WireGuard Tunnel)..."

# 1. Check if namespaces exist
if ! ip netns list | grep -q "ns1" || ! ip netns list | grep -q "ns2"; then
    echo "[FAIL] Namespaces ns1 or ns2 do not exist."
    exit 1
fi

# 2. Check if wg0 interface exists in both namespaces
if ! ip netns exec ns1 ip link show wg0 >/dev/null 2>&1 || ! ip netns exec ns2 ip link show wg0 >/dev/null 2>&1; then
    echo "[FAIL] wg0 interface is missing in one of the namespaces."
    exit 1
fi
echo "  [OK] namespaces and wg0 interfaces are present."

# 3. Check handshake
handshake=$(ip netns exec ns1 wg show wg0 transfer 2>/dev/null || true)
# Trigger a ping to ensure handshake occurs
ip netns exec ns1 ping -c 2 -W 1 192.168.100.2 >/dev/null 2>&1 || true

wg_status=$(ip netns exec ns1 wg show wg0)
if echo "$wg_status" | grep -q "latest handshake"; then
    echo "  [OK] WireGuard tunnel established successfully (handshake detected)."
    echo "✅ Lab 3 Verification Successful!"
    exit 0
else
    echo "[FAIL] WireGuard tunnel handshake is missing."
    echo "Current status:"
    echo "$wg_status"
    exit 1
fi
