#!/bin/bash
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Запусти через sudo/root (нужны netns/iptables)"; exit 1; }

# Check and install dependencies
if ! command -v iperf3 &>/dev/null || ! command -v tc &>/dev/null || ! command -v ping &>/dev/null; then
    echo "Installing dependencies..."
    apt-get update >/dev/null 2>&1 || true
    DEBIAN_FRONTEND=noninteractive apt-get install -y iperf3 iproute2 iputils-ping >/dev/null 2>&1
else
    echo "Dependencies (iperf3, tc, ping) are already installed."
fi

ip netns del client 2>/dev/null || true
ip netns del server 2>/dev/null || true

echo "Создание Network Namespaces (client, server)..."
ip netns add client
ip netns add server

echo "Создание veth пары..."
ip link add veth-cli type veth peer name veth-srv

ip link set veth-cli netns client
ip link set veth-srv netns server

ip netns exec client ip link set lo up
ip netns exec server ip link set lo up

ip netns exec client ip link set veth-cli up
ip netns exec server ip link set veth-srv up

ip netns exec client ip addr add 10.9.0.1/24 dev veth-cli
ip netns exec server ip addr add 10.9.0.2/24 dev veth-srv

echo "=========================================================="
echo "✅ Lab 9 (Traffic Control) Setup Complete!"
echo "client: 10.9.0.1"
echo "server: 10.9.0.2"
echo ""
echo "Проверьте базовый ping (должен быть < 1ms):"
echo "  ip netns exec client ping -c 3 10.9.0.2"
echo ""
echo "Далее переходите к README.md для симуляции сбоев!"
echo "=========================================================="
