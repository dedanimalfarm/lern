#!/bin/bash

# Clean up previous setup
ip netns del host1 2>/dev/null
ip netns del host2 2>/dev/null
ip netns del router 2>/dev/null
ip link del br0 2>/dev/null

echo "Setting up Network Namespaces (host1, host2, router)..."
ip netns add host1
ip netns add host2
ip netns add router

echo "Creating a Bridge (br0) acting as a switch..."
ip link add br0 type bridge
ip link set br0 up

echo "Connecting hosts and router to the switch..."
# Connect host1
ip link add veth-h1 type veth peer name veth-h1-br
ip link set veth-h1 netns host1
ip link set veth-h1-br master br0 up
ip -n host1 link set veth-h1 up

# Connect host2
ip link add veth-h2 type veth peer name veth-h2-br
ip link set veth-h2 netns host2
ip link set veth-h2-br master br0 up
ip -n host2 link set veth-h2 up

# Connect router
ip link add veth-r type veth peer name veth-r-br
ip link set veth-r netns router
ip link set veth-r-br master br0 up
ip -n router link set veth-r up

echo "Configuring VLAN 10 on host1..."
ip -n host1 link add link veth-h1 name veth-h1.10 type vlan id 10
ip -n host1 addr add 10.0.10.10/24 dev veth-h1.10
ip -n host1 link set veth-h1.10 up
ip -n host1 route add default via 10.0.10.1
ip -n host1 link set lo up

echo "Configuring VLAN 20 on host2..."
ip -n host2 link add link veth-h2 name veth-h2.20 type vlan id 20
ip -n host2 addr add 10.0.20.20/24 dev veth-h2.20
ip -n host2 link set veth-h2.20 up
ip -n host2 route add default via 10.0.20.1
ip -n host2 link set lo up

echo "=========================================================="
echo "✅ Lab 4 Phase 1 Complete!"
echo "host1 is on VLAN 10 (IP: 10.0.10.10)"
echo "host2 is on VLAN 20 (IP: 10.0.20.20)"
echo ""
echo "Try to ping host2 from host1 (this will fail as they are in different VLANs!):"
echo "  ip netns exec host1 ping -c 2 10.0.20.20"
echo "=========================================================="

echo "Configuring Router-on-a-stick for Inter-VLAN Routing..."
ip -n router link add link veth-r name veth-r.10 type vlan id 10
ip -n router addr add 10.0.10.1/24 dev veth-r.10
ip -n router link set veth-r.10 up

ip -n router link add link veth-r name veth-r.20 type vlan id 20
ip -n router addr add 10.0.20.1/24 dev veth-r.20
ip -n router link set veth-r.20 up
ip -n router link set lo up

echo "Enabling IP forwarding on the router..."
ip netns exec router sysctl -w net.ipv4.ip_forward=1 >/dev/null

echo "=========================================================="
echo "✅ Lab 4 Phase 2 Complete!"
echo "Router configured with gateways 10.0.10.1 and 10.0.20.1"
echo ""
echo "Try to ping host2 from host1 again (now it should work!):"
echo "  ip netns exec host1 ping -c 4 10.0.20.20"
echo "=========================================================="
