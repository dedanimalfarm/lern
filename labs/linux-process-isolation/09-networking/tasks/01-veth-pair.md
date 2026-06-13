# 01 — veth pair между двумя namespace

## Задача
Соединить два сетевых namespace veth-парой, назначить адреса из одной подсети и
добиться ping между ними напрямую (без моста).

## Проверка
```bash
ip netns add alpha; ip netns add beta
ip link add veth-a type veth peer name veth-b
ip link set veth-a netns alpha; ip link set veth-b netns beta
ip netns exec alpha sh -c 'ip addr add 10.55.0.1/24 dev veth-a; ip link set veth-a up; ip link set lo up'
ip netns exec beta  sh -c 'ip addr add 10.55.0.2/24 dev veth-b; ip link set veth-b up; ip link set lo up'
ip netns exec alpha ping -c2 -W1 10.55.0.2
ip netns del alpha; ip netns del beta
```

## Ожидаемый результат
```
64 bytes from 10.55.0.2: icmp_seq=1 ttl=64 time=0.082 ms
2 packets transmitted, 2 received, 0% packet loss
```
Что вошло в один конец veth — вышло из другого. Это L2-связь на двоих; для многих
контейнеров нужен мост (задание 02). Не забудь поднять ОБА конца (`ip link set up`).
