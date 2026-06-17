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
if ! ip netns exec host1 ping -c 2 -W 2 10.0.20.20 >/dev/null 2>&1; then
    echo "[FAIL] Inter-VLAN Routing verification failed. host1 cannot ping host2."
    exit 1
fi
echo "  [OK] Inter-VLAN Routing works. host1 can reach host2."

# 4. Verify 802.1q tags using tcpdump on br0
if ! command -v tcpdump &>/dev/null; then
    echo "  [WARNING] tcpdump is not installed. Skipping 802.1q tag packet inspection."
else
    vlan_packets_file=$(mktemp)
    # Capture 4 packets with VLAN headers on br0
    tcpdump -i br0 -e -n -c 4 vlan > "$vlan_packets_file" 2>/dev/null &
    tcpdump_pid=$!
    sleep 0.5
    
    # Generate VLAN traffic
    ip netns exec host1 ping -c 2 -W 1 10.0.20.20 >/dev/null 2>&1 || true
    
    # Wait for tcpdump to finish
    wait "$tcpdump_pid" 2>/dev/null || true
    
    # Check if packets contain expected tags
    if grep -q "vlan 10" "$vlan_packets_file" && grep -q "vlan 20" "$vlan_packets_file"; then
        echo "  [OK] 802.1q tags verified in network traffic (vlan 10 and vlan 20 detected)."
    else
        echo "[FAIL] 802.1q tags not detected in traffic."
        echo "Captured output:"
        cat "$vlan_packets_file"
        rm -f "$vlan_packets_file"
        exit 1
    fi
    rm -f "$vlan_packets_file"
fi

echo "✅ Lab 4 Verification Successful!"
exit 0
