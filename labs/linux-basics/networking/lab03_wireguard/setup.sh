#!/bin/bash

# Clean up previous setup
ip netns del ns1 2>/dev/null
ip netns del ns2 2>/dev/null

echo "Installing WireGuard and dependencies..."
apt-get update >/dev/null 2>&1
DEBIAN_FRONTEND=noninteractive apt-get install -y wireguard wireguard-tools iproute2 >/dev/null 2>&1

echo "Setting up Network Namespaces (ns1, ns2)..."
ip netns add ns1
ip netns add ns2

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
wg genkey | tee privatekey1 | wg pubkey > publickey1
wg genkey | tee privatekey2 | wg pubkey > publickey2

echo "Configuring WireGuard on ns1 (Peer 1)..."
ip -n ns1 link add dev wg0 type wireguard
ip -n ns1 addr add 192.168.100.1/24 dev wg0
ip netns exec ns1 wg set wg0 private-key ./privatekey1 peer $(cat publickey2) allowed-ips 192.168.100.2/32 endpoint 10.0.0.2:51820
ip netns exec ns1 wg set wg0 listen-port 51820
ip -n ns1 link set wg0 up

echo "Configuring WireGuard on ns2 (Peer 2)..."
ip -n ns2 link add dev wg0 type wireguard
ip -n ns2 addr add 192.168.100.2/24 dev wg0
ip netns exec ns2 wg set wg0 listen-port 51820 private-key ./privatekey2 peer $(cat publickey1) allowed-ips 192.168.100.1/32 endpoint 10.0.0.1:51820
ip -n ns2 link set wg0 up

rm privatekey1 privatekey2 publickey1 publickey2

echo "=========================================================="
echo "✅ Lab 3 Setup Complete!"
echo "Tunnel network: 192.168.100.0/24"
echo "ns1 VPN IP: 192.168.100.1"
echo "ns2 VPN IP: 192.168.100.2"
echo "Test connection:"
echo "  ip netns exec ns1 ping 192.168.100.2"
echo "=========================================================="
