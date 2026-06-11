#!/bin/bash
echo "Installing dependencies..."
apt-get update > /dev/null 2>&1
DEBIAN_FRONTEND=noninteractive apt-get install -y haproxy python3 curl > /dev/null 2>&1

echo "Creating directories for web servers..."
mkdir -p /tmp/web1 /tmp/web2 /tmp/web3
echo "Hello from Server 1" > /tmp/web1/index.html
echo "Hello from Server 2" > /tmp/web2/index.html
echo "Hello from Server 3" > /tmp/web3/index.html

echo "Starting Python web servers..."
# Kill existing ones if any
pkill -f "http.server 808" 2>/dev/null
nohup python3 -m http.server 8081 --directory /tmp/web1 > /dev/null 2>&1 &
nohup python3 -m http.server 8082 --directory /tmp/web2 > /dev/null 2>&1 &
nohup python3 -m http.server 8083 --directory /tmp/web3 > /dev/null 2>&1 &
sleep 1

echo "Starting HAProxy..."
killall haproxy 2>/dev/null
haproxy -f ./haproxy.cfg -D

echo "=========================================================="
echo "✅ Lab 2 Setup Complete!"
echo "Backend web servers running on ports: 8081, 8082, 8083"
echo "HAProxy Load Balancer running on port: 8080"
echo "Try running: curl http://localhost:8080"
echo "=========================================================="
