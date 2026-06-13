# 03 — NAT: выход контейнера в интернет

## Задача
Дать контейнеру с приватным адресом (`10.55.0.0/24`) выход во внешний мир через
MASQUERADE на хосте, включив IP-форвардинг.

> Требует, чтобы у самого хоста был выход в интернет.

## Проверка
```bash
# (мост lab-br + netns alpha с адресом 10.55.0.1 и default route via 10.55.0.254 — из задания 02)
sysctl -w net.ipv4.ip_forward=1
iptables -t nat -A POSTROUTING -s 10.55.0.0/24 -j MASQUERADE
ip netns exec alpha ping -c2 -W2 1.1.1.1
```

## Ожидаемый результат
```
64 bytes from 1.1.1.1: icmp_seq=1 ttl=... time=4.0 ms
2 packets transmitted, 2 received, 0% packet loss
```
Пакеты alpha уходят наружу с IP хоста (MASQUERADE = SNAT с автоподстановкой адреса
исходящего интерфейса), а `ip_forward=1` разрешает хосту роутить между
интерфейсами. Это и есть outbound-сеть Docker-контейнера.
