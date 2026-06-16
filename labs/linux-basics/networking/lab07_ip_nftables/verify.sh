#!/bin/bash
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Запусти через sudo/root"; exit 1; }

echo "Verifying Lab 7 (iptables / nftables)..."

# 1. Check if namespaces exist
for ns in web app db; do
    if ! ip netns list | grep -q "$ns"; then
        echo "[FAIL] Namespace $ns does not exist!"
        exit 1
    fi
done

# 2. Check base connectivity (web -> bridge gateway)
if ! ip netns exec web ping -c 2 -W 1 10.0.0.1 >/dev/null 2>&1; then
    echo "[FAIL] Cannot ping bridge gateway (10.0.0.1) from web namespace."
    exit 1
fi
echo "  [OK] Network namespaces and L2 bridge are up."

# 3. Check IP forwarding
forward=$(sysctl -n net.ipv4.ip_forward)
if [ "$forward" != "1" ]; then
    echo "[FAIL] IP forwarding is disabled!"
    exit 1
fi
echo "  [OK] IP forwarding is enabled."

# 4. Check if either iptables rules or nftables rules are loaded
iptables_rules=$(iptables -t filter -S | wc -l)
nftables_rules=$(nft list ruleset 2>/dev/null | wc -l || echo 0)

if [ "$iptables_rules" -le 3 ] && [ "$nftables_rules" -le 0 ]; then
    echo "[FAIL] No custom firewall rules (iptables or nftables) are loaded."
    exit 1
fi
echo "  [OK] Firewall rules are active (iptables size: $iptables_rules, nftables size: $nftables_rules)."

echo "✅ Lab 7 Verification Successful!"
exit 0
