#!/bin/bash

# Установка CNI плагинов
CNI_DIR="/opt/cni/bin"
CNI_VERSION="v1.3.0"

if [ ! -f "$CNI_DIR/bridge" ]; then
    echo "Скачиваем официальные CNI плагины (v1.3.0)..."
    mkdir -p $CNI_DIR
    wget -qO cni-plugins.tgz "https://github.com/containernetworking/plugins/releases/download/$CNI_VERSION/cni-plugins-linux-amd64-$CNI_VERSION.tgz"
    tar -xzf cni-plugins.tgz -C $CNI_DIR
    rm cni-plugins.tgz
fi

# Подготовка
NS="cni-ns"
ip netns del $NS 2>/dev/null
ip link del cni-br0 2>/dev/null

echo "Создаем Network Namespace: $NS"
ip netns add $NS

echo "Создаем конфигурацию CNI (my-cni-config.json)..."
cat <<EOF > my-cni-config.json
{
    "cniVersion": "0.4.0",
    "name": "my-cni-network",
    "type": "bridge",
    "bridge": "cni-br0",
    "isGateway": true,
    "ipMasq": true,
    "ipam": {
        "type": "host-local",
        "subnet": "10.22.0.0/24",
        "routes": [
            { "dst": "0.0.0.0/0" }
        ]
    }
}
EOF

echo "Вызываем CNI плагин ВРУЧНУЮ (CNI_COMMAND=ADD)..."
# Устанавливаем переменные окружения, которые обычно устанавливает Kubelet
export CNI_COMMAND=ADD
export CNI_CONTAINERID=my-cni-container-123
export CNI_NETNS=/var/run/netns/$NS
export CNI_IFNAME=eth0
export CNI_PATH=$CNI_DIR

# Передаем JSON-конфиг плагину 'bridge' через STDIN
cat my-cni-config.json | $CNI_DIR/bridge > cni_output.json

echo ""
echo "Результат, который вернул CNI плагин (в формате JSON):"
cat cni_output.json | jq . 2>/dev/null || cat cni_output.json
echo ""

echo "=========================================================="
echo "✅ Lab 12 Setup Complete!"
echo "CNI плагин отработал. Давайте проверим сеть в namespace '$NS':"
echo "  ip netns exec $NS ip a"
echo "  ip netns exec $NS ip route"
echo ""
echo "Проверьте пинг до шлюза (моста на хосте):"
echo "  ip netns exec $NS ping -c 2 10.22.0.1"
echo "=========================================================="
