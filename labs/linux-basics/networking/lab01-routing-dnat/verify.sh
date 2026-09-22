#!/bin/bash

echo "Verifying DNAT and Routing..."

# Check if curl works
OUTPUT=$(ip netns exec client_ns curl -s --max-time 2 http://10.0.1.1:80 || true)

if echo "$OUTPUT" | grep -q "Hello from Internal Server!"; then
    echo "[OK] Routing and DNAT are working correctly!"
    exit 0
else
    echo "[FAIL] Could not reach the internal server from client_ns."
    echo "Check your routes, ip_forward, and iptables rules."
    exit 1
fi
