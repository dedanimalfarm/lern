#!/bin/bash
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Запусти через sudo/root (нужны netns/iptables)"; exit 1; }

# Clean up previous setup
echo "Cleaning up previous processes..."
pkill -f "http.server 808" || true
killall haproxy || true

# Check and install dependencies
if ! command -v haproxy &>/dev/null || ! command -v python3 &>/dev/null || ! command -v curl &>/dev/null; then
    echo "Installing dependencies..."
    apt-get update > /dev/null 2>&1 || true
    DEBIAN_FRONTEND=noninteractive apt-get install -y haproxy python3 curl > /dev/null 2>&1
else
    echo "Dependencies (HAProxy, Python3, curl) are already installed."
fi

echo "Creating directories for web servers..."
mkdir -p /tmp/web1 /tmp/web2 /tmp/web3
echo "Hello from Server 1" > /tmp/web1/index.html
echo "Hello from Server 2" > /tmp/web2/index.html
echo "Hello from Server 3" > /tmp/web3/index.html

echo "Starting Python web servers..."
setsid python3 -m http.server 8081 --directory /tmp/web1 > /dev/null 2>&1 &
setsid python3 -m http.server 8082 --directory /tmp/web2 > /dev/null 2>&1 &
setsid python3 -m http.server 8083 --directory /tmp/web3 > /dev/null 2>&1 &

sleep 1

echo "Starting HAProxy..."
haproxy -f ./haproxy.cfg -D

echo "Verifying Load Balancer (sending 6 requests)..."
sleep 1
success=true
for i in {1..6}; do
    response=$(curl -s --connect-timeout 2 http://localhost:8080 || echo "FAILED")
    if [ "$response" = "FAILED" ]; then
        success=false
        echo "  Request $i: FAILED to connect"
    else
        echo "  Request $i: $response"
    fi
done

if [ "$success" = true ]; then
    echo "=========================================================="
    echo "✅ Lab 2 Setup Complete & Verified!"
    echo "Backend web servers running on ports: 8081, 8082, 8083"
    echo "HAProxy Load Balancer running on port: 8080"
    echo "Test connection manually:"
    echo "  curl http://localhost:8080"
    echo "=========================================================="
else
    echo "❌ Lab 2 Setup Failed: Connection verification failed!" >&2
    exit 1
fi
