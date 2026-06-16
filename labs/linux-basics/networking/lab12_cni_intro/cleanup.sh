#!/usr/bin/env bash
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Запусти через sudo/root"; exit 1; }

echo "Cleaning up Lab 12 (CNI Introduction) namespaces and bridge..."
if ip link show cni-br0 >/dev/null 2>&1; then
    for port in $(ip link show master cni-br0 | awk -F': ' '/^[0-9]+:/ {print $2}' | cut -d'@' -f1); do
        ip link del "$port" 2>/dev/null || true
    done
fi
# Clean up any remaining host-side CNI veths (matching veth + 8 hex chars)
for link in $(ip -o link show | awk -F': ' '{print $2}' | cut -d'@' -f1 | grep -E "^veth[0-9a-f]{8}$"); do
    ip link del "$link" 2>/dev/null || true
done
ip netns del cni-ns 2>/dev/null || true
ip link del cni-br0 2>/dev/null || true
rm -rf /var/lib/cni/networks/my-cni-network
rm -f my-cni-config.json cni_output.json
echo "✅ Lab 12 cleanup complete."
