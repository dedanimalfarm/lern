#!/bin/bash

export DEBIAN_FRONTEND=noninteractive
BRIDGE="docker-br0"
SUBNET="10.11.0"
IP_FILE="/tmp/mini-docker-ip.txt"

setup_bridge() {
    if ! ip link show $BRIDGE >/dev/null 2>&1; then
        echo "[mini-docker] Создание сети $BRIDGE..."
        ip link add $BRIDGE type bridge
        ip addr add $SUBNET.1/24 dev $BRIDGE
        ip link set $BRIDGE up
        
        # Настройка NAT для выхода контейнеров в интернет
        sysctl -w net.ipv4.ip_forward=1 >/dev/null
        sysctl -w net.ipv4.conf.all.route_localnet=1 >/dev/null
        DEFAULT_IFACE=$(ip route show default | awk '/default/ {print $5}' | head -1)
        iptables -t nat -A POSTROUTING -s $SUBNET.0/24 -o $DEFAULT_IFACE -j MASQUERADE
        echo 2 > $IP_FILE
    fi
}

run_container() {
    NAME=$1
    PORTS=$2 # format HOST_PORT:CONTAINER_PORT
    
    if ip netns list | grep -q "^$NAME "; then
        echo "Контейнер $NAME уже существует!"
        exit 1
    fi
    
    setup_bridge
    
    HOST_PORT=$(echo $PORTS | cut -d':' -f1)
    CONT_PORT=$(echo $PORTS | cut -d':' -f2)
    
    IP_SUFFIX=$(cat $IP_FILE)
    CONT_IP="$SUBNET.$IP_SUFFIX"
    echo $((IP_SUFFIX + 1)) > $IP_FILE

    echo "[mini-docker] Запуск контейнера '$NAME' ($CONT_IP) с пробросом $HOST_PORT -> $CONT_PORT..."
    
    ip netns add $NAME
    ip netns exec $NAME ip link set lo up
    
    # veth pair
    ip link add veth-$NAME type veth peer name eth0
    ip link set veth-$NAME master $BRIDGE
    ip link set veth-$NAME up
    
    ip link set eth0 netns $NAME
    ip netns exec $NAME ip link set eth0 up
    ip netns exec $NAME ip addr add $CONT_IP/24 dev eth0
    ip netns exec $NAME ip route add default via $SUBNET.1
    
    # Port Forwarding (DNAT)
    if [ ! -z "$HOST_PORT" ] && [ ! -z "$CONT_PORT" ]; then
        iptables -t nat -A PREROUTING -p tcp --dport $HOST_PORT -j DNAT --to-destination $CONT_IP:$CONT_PORT
        
        # Для доступности через localhost (loopback routing)
        iptables -t nat -A OUTPUT -o lo -p tcp --dport $HOST_PORT -j DNAT --to-destination $CONT_IP:$CONT_PORT
        iptables -t nat -A POSTROUTING -s 127.0.0.1 -d $CONT_IP -p tcp --dport $CONT_PORT -j MASQUERADE
    fi
    
    # Запускаем payload в фоне: простой веб-сервер
    mkdir -p /tmp/mini-docker-$NAME
    echo "Hello from mini-docker container $NAME!" > /tmp/mini-docker-$NAME/index.html
    ip netns exec $NAME python3 -m http.server $CONT_PORT --directory /tmp/mini-docker-$NAME >/dev/null 2>&1 &
    
    # Сохраняем PID
    echo $! > /tmp/mini-docker-$NAME.pid
    echo "[mini-docker] Контейнер успешно запущен!"
}

stop_container() {
    NAME=$1
    if ! ip netns list | grep -q "^$NAME "; then
        echo "Контейнер $NAME не найден!"
        exit 1
    fi
    
    echo "[mini-docker] Остановка контейнера '$NAME'..."
    PID=$(cat /tmp/mini-docker-$NAME.pid 2>/dev/null)
    if [ ! -z "$PID" ]; then
        kill $PID 2>/dev/null
    fi
    rm -rf /tmp/mini-docker-$NAME*
    
    ip netns del $NAME
    # Note: В реальном докере iptables правила бы удалялись, мы для упрощения оставляем.
    echo "[mini-docker] Контейнер удален."
}

if [ "$1" == "run" ]; then
    run_container $2 $3
elif [ "$1" == "stop" ]; then
    stop_container $2
else
    echo "Usage: bash mini-docker.sh <run|stop> <name> [HOST_PORT:CONTAINER_PORT]"
fi
