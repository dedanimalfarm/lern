#!/bin/bash
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Запусти через sudo/root"; exit 1; }

echo "Verifying Lab 10 (BGP BIRD Routing)..."

# 1. Check if namespaces exist
for ns in r1 r2 r3; do
    if ! ip netns list | grep -q "$ns"; then
        echo "[FAIL] Namespace $ns does not exist!"
        exit 1
    fi
done

# 2. Check if bird control files exist
for ns in r1 r2 r3; do
    if [ ! -S "/tmp/bird-$ns.ctl" ]; then
        echo "[FAIL] BIRD control socket for $ns (/tmp/bird-$ns.ctl) is missing."
        exit 1
    fi
done
echo "  [OK] Namespaces and BIRD processes are up."

# 3. Check BGP routes in r1
# Give it a tiny moment to settle BGP sessions if recently started
sleep 2
routes=$(ip netns exec r1 ip route)
echo "  Current r1 routes:"
echo "$routes"

if echo "$routes" | grep -q "10.3.0.0/24.*proto bird"; then
    echo "  [OK] Route to 10.3.0.0/24 propagated via BIRD (BGP)."
    
    # Try pinging from r1 to r3's dummy network
    if ip netns exec r1 ping -c 2 -W 1 10.3.0.1 >/dev/null 2>&1; then
        echo "  [OK] Ping from r1 to 10.3.0.1 (r3 dummy network) works."
        echo "✅ Lab 10 Verification Successful!"
        exit 0
    else
        echo "[FAIL] BGP route is present, but ping to 10.3.0.1 failed."
        exit 1
    fi
else
    echo "[FAIL] BIRD (BGP) route to 10.3.0.0/24 is missing in r1 routing table."
    exit 1
fi
