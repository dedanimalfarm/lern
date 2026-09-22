#!/bin/bash
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Запусти через sudo/root (нужны netns/iptables)"; exit 1; }

# Check dependencies
for cmd in ip sysctl iptables nft; do
    command -v "$cmd" &>/dev/null || { echo "❌ Missing dependency: $cmd" >&2; exit 1; }
done

echo "ВНИМАНИЕ: скрипт очищает ВСЕ правила iptables на этой машине."
echo "Не запускайте его там, где работают Docker, Kubernetes или боевой firewall."

# Clean up previous setup
for NS in web app db; do
    ip netns del $NS 2>/dev/null || true
done
ip link del br0 2>/dev/null || true
iptables -F
iptables -t nat -F
iptables -F FORWARD

echo "Создание Network Namespaces..."
ip netns add web
ip netns add app
ip netns add db

echo "Создание виртуального свитча (bridge)..."
ip link add br0 type bridge
ip link set br0 up
ip addr add 10.0.0.1/24 dev br0

echo "Подключение namespaces к bridge..."
IP_SUFFIX=2
for NS in web app db; do
    ip netns exec $NS ip link set lo up

    # Создаем veth-пару (сохраняем оригинальные имена интерфейсов как в README)
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
    
    ((IP_SUFFIX++))
done

echo "Включение маршрутизации и NAT на хосте..."
sysctl -w net.ipv4.ip_forward=1 >/dev/null

echo "Включение br_netfilter (без него правила FORWARD не увидят трафик внутри моста)..."
modprobe br_netfilter 2>/dev/null || true
if ! sysctl -w net.bridge.bridge-nf-call-iptables=1 >/dev/null 2>&1; then
    echo "❌ Не удалось включить net.bridge.bridge-nf-call-iptables." >&2
    echo "   Задания 3, 6, 7, 10, 12 и 14 работать не будут: трафик между" >&2
    echo "   namespace'ами коммутируется мостом и в цепочку FORWARD не попадает." >&2
    exit 1
fi
DEFAULT_IFACE=$(ip route show default | awk '/default/ {print $5}' | head -1)
iptables -t nat -A POSTROUTING -s 10.0.0.0/24 -o $DEFAULT_IFACE -j MASQUERADE

echo "=========================================================="
echo "✅ Lab 7 Setup Complete!"
echo "Bridge br0: 10.0.0.1/24"
echo "br_netfilter: включён (bridge-nf-call-iptables=1)"
echo "web: 10.0.0.2 (dev eth0-web)"
echo "app: 10.0.0.3 (dev eth0-app)"
echo "db:  10.0.0.4 (dev eth0-db)"
echo ""
echo "Теперь вы можете выполнять команды iptables/nftables"
echo "из README.md для настройки фаервола!"
echo "=========================================================="
