#!/bin/bash
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Запусти через sudo/root"; exit 1; }

echo "Verifying Lab 6 (Linux Bridge)..."

# 1. Check if namespaces exist
for ns in red blue green; do
    if ! ip netns list | grep -q "$ns"; then
        echo "[FAIL] Namespace $ns does not exist!"
        exit 1
    fi
done

# 2. Check ping between namespaces (red to blue)
if ! ip netns exec red ping -c 2 -W 1 10.0.0.3 >/dev/null 2>&1; then
    echo "[FAIL] Cannot ping blue (10.0.0.3) from red namespace."
    exit 1
fi
echo "  [OK] Ping between namespaces red -> blue works."

# 3. Check ping to bridge gateway
if ! ip netns exec red ping -c 2 -W 1 10.0.0.1 >/dev/null 2>&1; then
    echo "[FAIL] Cannot ping bridge gateway (10.0.0.1) from red namespace."
    exit 1
fi
echo "  [OK] Ping red -> gateway (br0) works."

# 4. Check internet connectivity via NAT
if ! ip netns exec red ping -c 2 -W 2 8.8.8.8 >/dev/null 2>&1; then
    echo "[FAIL] Internet connection (NAT) from red namespace failed."
    echo "Check iptables MASQUERADE rules and ip_forward."
    exit 1
fi
echo "  [OK] Internet connectivity (NAT) works."

echo "✅ Lab 6 Verification Successful!"
exit 0
