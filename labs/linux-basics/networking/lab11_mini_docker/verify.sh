#!/bin/bash
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Запусти через sudo/root"; exit 1; }

echo "Verifying Lab 11 (Mini Docker)..."

# 1. Check if bridge docker-br0 exists
if ! ip link show docker-br0 >/dev/null 2>&1; then
    echo "[FAIL] Bridge docker-br0 does not exist!"
    exit 1
fi
echo "  [OK] docker-br0 bridge exists."

# 2. Check if there are running containers (any network namespaces other than host/standard ones)
containers=$(ip netns list | awk '{print $1}')
if [ -z "$containers" ]; then
    echo "[FAIL] No running namespaces (mini-docker containers) found."
    exit 1
fi

echo "  Running containers: $containers"

# 3. Test connection to one of the containers
# Usually they run a container with port 8080 forwarded to 80
# Let's try to connect to localhost:8080 or look at iptables nat rules to find the forwarded port
forwarded_port=$(iptables -t nat -S | grep -oP '(?<=--dport )\d+' | head -n1 || true)
if [ -z "$forwarded_port" ]; then
    # If no DNAT port found, check connection directly to container IP
    container_ip=$(ip netns exec $(echo "$containers" | head -n1) ip -4 addr show eth0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}' || true)
    if [ -n "$container_ip" ]; then
        if curl -s --max-time 2 http://$container_ip:80 | grep -q "Hello from mini-docker"; then
            echo "  [OK] Container is directly reachable at http://$container_ip:80"
            echo "✅ Lab 11 Verification Successful!"
            exit 0
        fi
    fi
    echo "[FAIL] No port forwarding rule found and container IP is unreachable."
    exit 1
fi

echo "  Detected forwarded port: $forwarded_port"
if curl -s --max-time 2 http://localhost:$forwarded_port | grep -q "Hello from mini-docker"; then
    echo "  [OK] Port forwarding to container is working (localhost:$forwarded_port responds correctly)."
    echo "✅ Lab 11 Verification Successful!"
    exit 0
else
    echo "[FAIL] Port forwarding is configured for port $forwarded_port but connection failed or returned invalid response."
    exit 1
fi
