# 03 — Изолировать сеть: --private-network

## Задача
Увидеть, что по умолчанию nspawn НЕ изолирует сеть (контейнер видит интерфейсы
хоста), а `--private-network` даёт пустой сетевой стек (только `lo`).

## Проверка
```bash
A=/lab/10/alpine
echo "по умолчанию (общий net-ns):"
systemd-nspawn -q -D "$A" --pipe -- /bin/sh -c 'ip -o link | wc -l'
echo "с --private-network (свой net-ns):"
systemd-nspawn -q --private-network -D "$A" --pipe -- /bin/sh -c 'ip -o link | wc -l'
```

## Ожидаемый результат
```
по умолчанию (общий net-ns):
7                         # интерфейсы ХОСТА (eth0, docker0, ...) — сеть не изолирована
с --private-network (свой net-ns):
1                         # только lo — свой пустой сетевой стек
```
Дефолт nspawn — общий net-ns (удобно для системных контейнеров). `--private-network`
= `--network=none` у Docker; `--network-veth`/`--network-bridge` подключают veth
наружу (как этап 09). Это сознательный выбор, а не баг.
