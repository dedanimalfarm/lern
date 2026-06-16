# Lab 9: Chaos Engineering & Traffic Control (tc)

В этой лабораторной работе мы изучим, как симулировать "плохую" сеть с помощью утилиты `tc` (Traffic Control) из пакета `iproute2`. Это критически важный навык для проверки отказоустойчивости приложений (Chaos Engineering).

## Запуск лабы
Сначала запустим скрипт, который создаст базовую топологию (два неймспейса, соединенных напрямую).
```bash
cd /root/lern/labs/linux-basics/networking/lab09_traffic_control
bash setup.sh
```

Вы получите два хоста: `client` (10.9.0.1) и `server` (10.9.0.2).

---

## Задание 1: Задержка (Latency)
Идеальная сеть не существует. Давайте добавим 100мс задержки ко всем пакетам, исходящим от сервера.

На хосте `server` применим правило (qdisc = queueing discipline) типа `netem` (Network Emulator):
```bash
ip netns exec server tc qdisc add dev veth-srv root netem delay 100ms
```

**Проверка:**
Сделайте пинг с клиента:
```bash
ip netns exec client ping 10.9.0.2
```
*Вы увидите, что `time=` теперь стабильно больше 100ms.*

**Удаление правила:**
```bash
ip netns exec server tc qdisc del dev veth-srv root
```

---

## Задание 2: Потеря пакетов (Packet Loss)
Сымитируем радиоканал или перегруженный свитч — сделаем так, чтобы 20% пакетов случайным образом терялись.

```bash
ip netns exec server tc qdisc add dev veth-srv root netem loss 20%
```

**Проверка:**
Запустите `ping` на 10-20 пакетов:
```bash
ip netns exec client ping -c 20 10.9.0.2
```
*В статистике вы увидите `~20% packet loss`.*

**Удаление правила:**
```bash
ip netns exec server tc qdisc del dev veth-srv root
```

---

## Задание 3: Ограничение скорости (Bandwidth Shaping)
С помощью дисциплины `tbf` (Token Bucket Filter) мы урежем скорость канала до 1 Мегабита в секунду. Это полезно для проверки, как приложение ведет себя при "бутылочном горлышке".

```bash
ip netns exec server tc qdisc add dev veth-srv root tbf rate 1mbit burst 32kbit latency 400ms
```

**Проверка скорости:**
Мы можем проверить скорость с помощью `iperf3`. Запустим сервер на `server` и клиент на `client`.

В одном окне терминала:
```bash
ip netns exec server iperf3 -s
```

В другом окне:
```bash
ip netns exec client iperf3 -c 10.9.0.2
```
*Вы увидите, что Bitrate стабильно держится на уровне 1 Mbits/sec.*

> **Не забудьте удалить правила после тестов:**
> `ip netns exec server tc qdisc del dev veth-srv root`


## Проверка модуля

Запустите проверочный скрипт, чтобы убедиться, что всё настроено верно:

```bash
sudo ./verify.sh
```

## Уборка

Для очистки системы от созданных ресурсов выполните:

```bash
sudo ./cleanup.sh
```

