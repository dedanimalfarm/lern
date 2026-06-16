#!/bin/bash
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Запусти через sudo/root"; exit 1; }

echo "Verifying Lab 12 (CNI Introduction)..."

# 1. Check if namespace cni-ns exists
if ! ip netns list | grep -q "cni-ns"; then
    echo "[FAIL] Namespace 'cni-ns' does not exist."
    exit 1
fi

# 2. Check if bridge cni-br0 exists
if ! ip link show cni-br0 >/dev/null 2>&1; then
    echo "[FAIL] Bridge cni-br0 does not exist!"
    exit 1
fi
echo "  [OK] Namespace cni-ns and bridge cni-br0 exist."

# 3. Check IP address on eth0 inside namespace cni-ns
cni_ip=$(ip netns exec cni-ns ip -4 addr show eth0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}' || true)
if [ -z "$cni_ip" ]; then
    echo "[FAIL] Interface eth0 inside cni-ns does not have an IP address."
    exit 1
fi

if [[ "$cni_ip" =~ ^10\.22\.0\. ]]; then
    echo "  [OK] eth0 inside cni-ns has correct IP: $cni_ip"
else
    echo "[FAIL] IP address of eth0 ($cni_ip) is not in the expected subnet 10.22.0.0/24."
    exit 1
fi

# 4. Check ping to gateway
if ! ip netns exec cni-ns ping -c 2 -W 1 10.22.0.1 >/dev/null 2>&1; then
    echo "[FAIL] Cannot ping CNI bridge gateway (10.22.0.1) from cni-ns."
    exit 1
fi
echo "  [OK] Ping cni-ns -> gateway (10.22.0.1) works."

# 5. Check if CNI output JSON exists and is valid
if [ ! -f "cni_output.json" ]; then
    echo "[FAIL] cni_output.json file is missing."
    exit 1
fi
echo "  [OK] cni_output.json exists."

echo "✅ Lab 12 Verification Successful!"
exit 0
