#!/bin/bash
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Запусти через sudo/root (нужны netns/iptables)"; exit 1; }

# Clean up previous setup
echo "Cleaning up previous network namespaces..."
ip netns del ns1 2>/dev/null || true
ip netns del ns2 2>/dev/null || true

# Check and install dependencies
if ! command -v wg &>/dev/null || ! command -v ip &>/dev/null; then
    echo "Installing WireGuard and dependencies..."
    apt-get update >/dev/null 2>&1 || true
    DEBIAN_FRONTEND=noninteractive apt-get install -y wireguard wireguard-tools iproute2 >/dev/null 2>&1
else
    echo "Dependencies (WireGuard and iproute2) are already installed."
fi

# Set up Network Namespaces
echo "Setting up Network Namespaces (ns1, ns2)..."
ip netns add ns1
ip netns add ns2

# Create secure temporary directory for keys
KEY_DIR=$(mktemp -d -t wg-keys-XXXXXX)
chmod 700 "$KEY_DIR"
trap 'rm -rf "$KEY_DIR"' EXIT

echo "Creating underlay network (veth pair connecting namespaces)..."
ip link add veth1 type veth peer name veth2
ip link set veth1 netns ns1
ip link set veth2 netns ns2

# Configure underlay IPs (public IPs simulation)
ip -n ns1 addr add 10.0.0.1/24 dev veth1
ip -n ns1 link set veth1 up
ip -n ns1 link set lo up

ip -n ns2 addr add 10.0.0.2/24 dev veth2
ip -n ns2 link set veth2 up
ip -n ns2 link set lo up

echo "Generating WireGuard keys..."
wg genkey | tee "$KEY_DIR/privatekey1" | wg pubkey > "$KEY_DIR/publickey1"
wg genkey | tee "$KEY_DIR/privatekey2" | wg pubkey > "$KEY_DIR/publickey2"

echo "Configuring WireGuard on ns1 (Peer 1)..."
ip -n ns1 link add dev wg0 type wireguard
ip -n ns1 addr add 192.168.100.1/24 dev wg0
ip netns exec ns1 wg set wg0 private-key "$KEY_DIR/privatekey1" peer "$(cat "$KEY_DIR/publickey2")" allowed-ips 192.168.100.2/32 endpoint 10.0.0.2:51820
ip netns exec ns1 wg set wg0 listen-port 51820
ip -n ns1 link set wg0 up

echo "Configuring WireGuard on ns2 (Peer 2)..."
ip -n ns2 link add dev wg0 type wireguard
ip -n ns2 addr add 192.168.100.2/24 dev wg0
ip netns exec ns2 wg set wg0 listen-port 51820 private-key "$KEY_DIR/privatekey2" peer "$(cat "$KEY_DIR/publickey1")" allowed-ips 192.168.100.1/32 endpoint 10.0.0.1:51820
ip -n ns2 link set wg0 up

echo "Verifying WireGuard tunnel connection..."
# Give interfaces a moment to initialize
sleep 1
if ip netns exec ns1 ping -c 3 -W 2 192.168.100.2 >/dev/null; then
    echo "=========================================================="
    echo "✅ Lab 3 Setup Complete & Verified!"
    echo "Tunnel network: 192.168.100.0/24"
    echo "ns1 VPN IP: 192.168.100.1"
    echo "ns2 VPN IP: 192.168.100.2"
    echo "Test connection:"
    echo "  ip netns exec ns1 ping -c 4 192.168.100.2"
    echo "=========================================================="
else
    echo "❌ Lab 3 Setup Failed: Connection verification failed!" >&2
    exit 1
fi
