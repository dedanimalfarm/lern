#!/bin/bash

export DEBIAN_FRONTEND=noninteractive
apt-get update >/dev/null 2>&1
apt-get install -y bird2 iproute2 >/dev/null 2>&1

# Cleanup
for i in r1 r2 r3; do
    ip netns del $i 2>/dev/null
    kill $(cat /tmp/bird-$i.pid 2>/dev/null) 2>/dev/null
done

echo "Создание неймспейсов (r1, r2, r3)..."
ip netns add r1
ip netns add r2
ip netns add r3

# Enable forwarding
for i in r1 r2 r3; do
    ip netns exec $i sysctl -w net.ipv4.ip_forward=1 >/dev/null
    ip netns exec $i ip link set lo up
done

echo "Создание линков: r1 <-> r2 <-> r3"
ip link add veth-r1 type veth peer name veth-r2-1
ip link add veth-r2-2 type veth peer name veth-r3

ip link set veth-r1 netns r1
ip link set veth-r2-1 netns r2
ip link set veth-r2-2 netns r2
ip link set veth-r3 netns r3

# Присвоение IP
ip netns exec r1 ip addr add 192.168.12.1/30 dev veth-r1
ip netns exec r1 ip link set veth-r1 up

ip netns exec r2 ip addr add 192.168.12.2/30 dev veth-r2-1
ip netns exec r2 ip addr add 192.168.23.1/30 dev veth-r2-2
ip netns exec r2 ip link set veth-r2-1 up
ip netns exec r2 ip link set veth-r2-2 up

ip netns exec r3 ip addr add 192.168.23.2/30 dev veth-r3
ip netns exec r3 ip link set veth-r3 up

# Создаем фиктивные интерфейсы (имитация внутренних сетей)
ip netns exec r1 ip link add dummy0 type dummy
ip netns exec r1 ip addr add 10.1.0.1/24 dev dummy0
ip netns exec r1 ip link set dummy0 up

ip netns exec r3 ip link add dummy0 type dummy
ip netns exec r3 ip addr add 10.3.0.1/24 dev dummy0
ip netns exec r3 ip link set dummy0 up

echo "Настройка конфигураций BIRD..."
# r1 config
cat <<EOF > /tmp/bird-r1.conf
router id 192.168.12.1;
protocol device { scan time 10; }
protocol direct { ipv4; interface "dummy0"; }
protocol kernel { ipv4 { export all; }; learn; }
protocol bgp bgp_r2 {
    local 192.168.12.1 as 65001;
    neighbor 192.168.12.2 as 65002;
    ipv4 { import all; export all; };
}
EOF

# r2 config
cat <<EOF > /tmp/bird-r2.conf
router id 192.168.12.2;
protocol device { scan time 10; }
protocol direct { ipv4; }
protocol kernel { ipv4 { export all; }; learn; }
protocol bgp bgp_r1 {
    local 192.168.12.2 as 65002;
    neighbor 192.168.12.1 as 65001;
    ipv4 { import all; export all; };
}
protocol bgp bgp_r3 {
    local 192.168.23.1 as 65002;
    neighbor 192.168.23.2 as 65003;
    ipv4 { import all; export all; };
}
EOF

# r3 config
cat <<EOF > /tmp/bird-r3.conf
router id 192.168.23.2;
protocol device { scan time 10; }
protocol direct { ipv4; interface "dummy0"; }
protocol kernel { ipv4 { export all; }; learn; }
protocol bgp bgp_r2 {
    local 192.168.23.2 as 65003;
    neighbor 192.168.23.1 as 65002;
    ipv4 { import all; export all; };
}
EOF

echo "Запуск демонов BGP..."
ip netns exec r1 bird -c /tmp/bird-r1.conf -P /tmp/bird-r1.pid -s /tmp/bird-r1.ctl
ip netns exec r2 bird -c /tmp/bird-r2.conf -P /tmp/bird-r2.pid -s /tmp/bird-r2.ctl
ip netns exec r3 bird -c /tmp/bird-r3.conf -P /tmp/bird-r3.pid -s /tmp/bird-r3.ctl

# Дадим время на поднятие сессий BGP
sleep 3

echo "=========================================================="
echo "✅ Lab 10 (BGP Routing) Setup Complete!"
echo "r1 network: 10.1.0.0/24"
echo "r3 network: 10.3.0.0/24"
echo "BGP сессии установлены!"
echo "Откройте README.md для проверки маршрутов."
echo "=========================================================="
