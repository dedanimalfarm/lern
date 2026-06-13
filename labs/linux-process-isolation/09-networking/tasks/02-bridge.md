# 02 — bridge: несколько контейнеров в одной сети

## Задача
Собрать мост, подключить к нему два-три netns veth-парами и проверить ping между
ними. На хостах с `br_netfilter` (Docker/WSL2) добавить `FORWARD ACCEPT` — иначе
bridged-трафик молча дропается.

## Проверка
```bash
ip link add lab-br type bridge; ip link set lab-br up; ip addr add 10.55.0.254/24 dev lab-br
iptables -A FORWARD -i lab-br -j ACCEPT; iptables -A FORWARD -o lab-br -j ACCEPT
for ns in alpha beta; do
  ip netns add "$ns"; ip link add "veth-$ns" type veth peer name "br-$ns"
  ip link set "br-$ns" master lab-br; ip link set "br-$ns" up; ip link set "veth-$ns" netns "$ns"
done
ip netns exec alpha sh -c 'ip addr add 10.55.0.1/24 dev veth-alpha; ip link set veth-alpha up; ip link set lo up'
ip netns exec beta  sh -c 'ip addr add 10.55.0.2/24 dev veth-beta;  ip link set veth-beta up;  ip link set lo up'
ip netns exec alpha ping -c2 -W1 10.55.0.2
```

## Ожидаемый результат
```
2 packets transmitted, 2 received, 0% packet loss
```
Если БЕЗ `FORWARD ACCEPT` на Docker/WSL2-хосте — будет `100% packet loss` (см.
scenario-01-нюанс в Troubleshooting): `br_netfilter` гонит bridged-кадры через
iptables FORWARD, а там policy DROP. Уборка: `ip netns del alpha beta; ip link del lab-br`.
