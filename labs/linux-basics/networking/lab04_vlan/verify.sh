#!/bin/bash
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Запусти через sudo/root"; exit 1; }

echo "Verifying Lab 4 (VLAN Isolation & Routing)..."

# 1. Check if namespaces exist
for ns in host1 host2 router; do
    if ! ip netns list | grep -q "$ns"; then
        echo "[FAIL] Namespace $ns does not exist!"
        exit 1
    fi
done

# 2. Check L2 bridge exists
if ! ip link show br0 >/dev/null 2>&1; then
    echo "[FAIL] Bridge br0 does not exist!"
    exit 1
fi
echo "  [OK] Namespaces and bridge are present."

# 3. Test ping host1 -> host2 through router
if ip netns exec host1 ping -c 3 -W 2 10.0.20.20 >/dev/null 2>&1; then
    echo "  [OK] Inter-VLAN Routing works. host1 can reach host2."
    echo "✅ Lab 4 Verification Successful!"
    exit 0
else
    echo "[FAIL] Inter-VLAN Routing verification failed. host1 cannot ping host2."
    exit 1
fi
