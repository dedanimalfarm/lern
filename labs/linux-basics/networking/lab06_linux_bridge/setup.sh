#!/bin/bash
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Запусти через sudo/root (нужны netns/iptables)"; exit 1; }

# Check dependencies
for cmd in ip sysctl iptables; do
    command -v "$cmd" &>/dev/null || { echo "❌ Missing dependency: $cmd" >&2; exit 1; }
done

# Clean up previous setup
for NS in red blue green; do
    ip netns del $NS 2>/dev/null
done
ip link del br0 2>/dev/null

echo "Создание Network Namespaces..."
ip netns add red
ip netns add blue
ip netns add green

echo "Создание виртуального свитча (bridge)..."
ip link add br0 type bridge
ip link set br0 up
ip addr add 10.0.0.1/24 dev br0

echo "Подключение namespaces к bridge..."
IP_SUFFIX=2
for NS in red blue green; do
    # Настраиваем loopback
    ip netns exec $NS ip link set lo up

    # Создаем veth-пару
    ip link add veth-$NS type veth peer name eth0-$NS
    
    # Один конец в мост
    ip link set veth-$NS master br0
    ip link set veth-$NS up
    
    # Другой конец в namespace
    ip link set eth0-$NS netns $NS
    ip netns exec $NS ip link set eth0-$NS up
    
    # Назначаем IP
    ip netns exec $NS ip addr add 10.0.0.${IP_SUFFIX}/24 dev eth0-$NS
    
    # Добавляем маршрут по умолчанию на хост (bridge)
    ip netns exec $NS ip route add default via 10.0.0.1
    
    # Настраиваем DNS
    mkdir -p /etc/netns/$NS
    echo "nameserver 8.8.8.8" > /etc/netns/$NS/resolv.conf
    
    ((IP_SUFFIX++))
done

echo "Включение маршрутизации и NAT на хосте..."
sysctl -w net.ipv4.ip_forward=1 >/dev/null
# Предполагаем, что интерфейс по умолчанию - первый с дефолтным маршрутом
DEFAULT_IFACE=$(ip route show default | awk '/default/ {print $5}' | head -1)
iptables -t nat -A POSTROUTING -s 10.0.0.0/24 -o $DEFAULT_IFACE -j MASQUERADE

echo "=========================================================="
echo "✅ Lab 6 Setup Complete!"
echo "Bridge br0: 10.0.0.1/24"
echo "red:   10.0.0.2"
echo "blue:  10.0.0.3"
echo "green: 10.0.0.4"
echo ""
echo "Test internet connection from 'red':"
echo "  ip netns exec red ping -c 2 8.8.8.8"
echo "=========================================================="
