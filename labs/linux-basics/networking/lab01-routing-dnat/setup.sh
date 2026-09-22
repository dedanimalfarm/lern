#!/bin/bash
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Запусти через sudo/root (нужны netns/iptables)"; exit 1; }

echo "Setting up Network Namespaces..."

# Create namespaces
ip netns add client_ns
ip netns add router_ns
ip netns add server_ns

# Create veth pairs
ip link add veth-c type veth peer name veth-r1
ip link add veth-s type veth peer name veth-r2

# Move interfaces to namespaces
ip link set veth-c netns client_ns
ip link set veth-r1 netns router_ns
ip link set veth-r2 netns router_ns
ip link set veth-s netns server_ns

# Configure client
ip netns exec client_ns ip addr add 10.0.1.2/24 dev veth-c
ip netns exec client_ns ip link set veth-c up
ip netns exec client_ns ip link set lo up

# Configure router
ip netns exec router_ns ip addr add 10.0.1.1/24 dev veth-r1
ip netns exec router_ns ip addr add 10.0.2.1/24 dev veth-r2
ip netns exec router_ns ip link set veth-r1 up
ip netns exec router_ns ip link set veth-r2 up
ip netns exec router_ns ip link set lo up

# Configure server
ip netns exec server_ns ip addr add 10.0.2.2/24 dev veth-s
ip netns exec server_ns ip link set veth-s up
ip netns exec server_ns ip link set lo up

# Start Python HTTP server in the background
ip netns exec server_ns bash -c "echo 'Hello from Internal Server!' > /tmp/index.html && cd /tmp && python3 -m http.server 8080 > /dev/null 2>&1 &"

echo "Setup complete!"
