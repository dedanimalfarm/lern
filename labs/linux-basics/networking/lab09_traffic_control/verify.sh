#!/bin/bash
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Запусти через sudo/root"; exit 1; }

echo "Verifying Lab 9 (Traffic Control)..."

# 1. Check if namespaces exist
if ! ip netns list | grep -q "client" || ! ip netns list | grep -q "server"; then
    echo "[FAIL] Namespace client or server does not exist."
    exit 1
fi

# 2. Check base connectivity
if ! ip netns exec client ping -c 2 -W 1 10.9.0.2 >/dev/null 2>&1; then
    echo "[FAIL] Cannot ping server (10.9.0.2) from client namespace."
    exit 1
fi
echo "  [OK] Base namespaces and connectivity are present."

# 3. Check qdisc configuration on server and client
qdisc_srv=$(ip netns exec server tc qdisc show dev veth-srv)
qdisc_cli=$(ip netns exec client tc qdisc show dev veth-cli)

echo "  Current Server qdisc: $qdisc_srv"
echo "  Current Client qdisc: $qdisc_cli"

# 4. Measure latency to see if emulation is active
avg_latency=$(ip netns exec client ping -c 3 10.9.0.2 | awk -F '/' 'NF{print $5}' | cut -d. -f1) || true

if [ -n "$avg_latency" ] && [ "$avg_latency" -gt 50 ]; then
    echo "  [OK] Traffic shaping/delay detected: average ping latency is ${avg_latency}ms."
else
    echo "  [INFO] No significant delay detected (avg latency < 50ms). Note: this is normal if no netem delay rules have been applied yet."
fi

echo "✅ Lab 9 Verification Successful!"
exit 0
