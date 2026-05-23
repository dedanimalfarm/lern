# 02 · Networking & firewall

> Тема из вакансии: «Базовое понимание сетей: IP, routing, NAT, firewall». «Настраивать сети (VLAN, bridges, firewall на базовом уровне)».

## Цель и навыки

После лабы ты:

- читаешь и редактируешь конфиг сети через **netplan** (Ubuntu 22.04 = netplan + systemd-networkd / NetworkManager);
- разбираешь, как выглядит таблица маршрутизации, и видишь разницу между `default route`, прямым маршрутом и LPM;
- настраиваешь правила `ufw` и понимаешь, во что они разворачиваются на уровне `iptables`/`nftables`;
- собираешь Linux-bridge и понимаешь его место в схеме «host ↔ VM/контейнер»;
- умеешь сделать **SNAT** (masquerade), когда нужно выпустить «внутреннюю» сеть наружу;
- диагностируешь «сервис не открывается» в правильном порядке: процесс → сокет → firewall → сеть.

## Теоретический минимум

**Стек сетевой подсистемы Linux** (снизу вверх): NIC → драйвер → netfilter (хук на conntrack/NAT/filter) → routing → сокет → процесс. На каждом уровне есть инструменты диагностики:

| Уровень          | Что отвечает                | Инструмент                                  |
|------------------|-----------------------------|---------------------------------------------|
| L2 (Ethernet)    | MAC, VLAN, bridge           | `ip link`, `bridge link`                    |
| L3 (IP)          | адреса, маршруты            | `ip addr`, `ip route`                       |
| L3.5 (netfilter) | firewall, NAT, conntrack    | `iptables -L`, `nft list ruleset`, `ufw status` |
| L4 (TCP/UDP)     | сокеты                      | `ss -tulnp`                                 |
| L7 (приложение)  | сам сервис                  | `journalctl -u`, `curl -v`                  |

**netplan** — декларативный YAML, который описывает желаемое состояние сети; рендерит конфиг для бэкенда (`systemd-networkd` на сервере или `NetworkManager` на десктопе). Файлы в `/etc/netplan/*.yaml`. Применить — `netplan try` (откатится через 120 с, если связь не восстановили) или `netplan apply`.

**ufw** — фронтенд над `iptables`/`nftables`. Полезен на одиночных серверах. На крупной инфре чаще пишут правила напрямую через `nft`/`iptables` или менеджеры конфигурации, но **читать `iptables-save`** ты обязан.

**Bridge** (`br0`) — программный L2-свитч. К нему «прицепляют» физический интерфейс и vNIC виртуалок/контейнеров — VM получает адрес из той же сети, что и хост. Альтернатива — NAT-сеть (libvirt `default`), где гости сидят в своей `192.168.122.0/24` и выходят через masquerade.

**NAT / masquerade** — переписывание исходного адреса исходящих пакетов на адрес внешнего интерфейса, плюс отслеживание сессий через conntrack. Нужен, когда внутренняя сеть не маршрутизируется снаружи (типичный домашний роутер).

## Базовая отработка

### Шаг 1. Карта сети «как сейчас»

```bash
ip -br addr             # один интерфейс на строку
ip -br link
ip route                # default + connected
resolvectl status | head -30   # DNS
ss -tulnp               # кто что слушает
```

Запиши: какой `default via`, какой DNS, какие порты слушаются. На свежей Ubuntu чаще всего: 22/tcp (ssh) и 53/tcp (systemd-resolved на 127.0.0.53).

### Шаг 2. netplan: статический IP в виде второго адреса

Не трогаем основной (DHCP) IP, добавим **secondary** статический. Это безопасно — потеря связи невозможна.

```bash
sudo tee /etc/netplan/90-lab.yaml >/dev/null <<'EOF'
network:
  version: 2
  ethernets:
    eth0:
      addresses:
        - 10.99.0.10/24
EOF
sudo chmod 0600 /etc/netplan/90-lab.yaml
sudo netplan try               # 120s rollback safety net
ip -br addr show eth0
```

> Имя интерфейса (`eth0`/`ens33`/`enp1s0`) узнай через `ip -br link` и подставь своё. netplan **требует** права `0600` на файл — иначе варнинг.

### Шаг 3. Маршруты и LPM

Добавь маршрут «как будто 10.99.0.0/24 идёт через VM саму себя» (бессмысленный, но безопасный пример — для тренировки):

```bash
sudo ip route add 10.123.0.0/24 dev eth0
ip route get 10.123.0.42        # покажет dev eth0, src ...
sudo ip route del 10.123.0.0/24
```

> `ip route get` — лучший способ ответить на вопрос «куда уйдёт этот пакет». Использует longest-prefix-match.

### Шаг 4. ufw — минимальный набор

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp comment 'ssh'
sudo ufw --force enable
sudo ufw status numbered verbose
sudo iptables -S | head -30      # увидишь сгенерированные правила
```

> **Порядок важен.** Сначала разрешаем 22, потом `enable`. Если сделать наоборот по ssh — отрежешь сессию. На прод-VPS используют `at`-команду для отложенного `ufw disable`, чтобы не залочиться:
> ```bash
> sudo bash -c 'echo "ufw --force reset" | at now + 5 minutes'
> sudo ufw enable
> # если потеряешь связь — через 5 минут ufw сбросится сам
> ```

### Шаг 5. Bridge собственными руками

Сделаем bridge без netplan — поэксперементируем «как оно работает на дне». **Не на eth0 с твоим SSH!** Создадим dummy-интерфейс.

```bash
sudo modprobe dummy
sudo ip link add dum0 type dummy
sudo ip link set dum0 up

sudo ip link add br-lab type bridge
sudo ip link set br-lab up
sudo ip link set dum0 master br-lab
sudo ip addr add 10.200.0.1/24 dev br-lab

bridge link
ip -br addr show br-lab
```

Теперь у тебя есть «свитч» `br-lab` с IP `10.200.0.1/24`. Сюда же будут цепляться tap-интерфейсы VM в лабе [04](../04-virtualization/).

Уборка:

```bash
sudo ip link del br-lab
sudo ip link del dum0
sudo rmmod dummy
```

## Расширенная отработка

### Задача 1. SNAT на ровном месте

Подними второй netns и пусти его наружу через masquerade.

```bash
sudo ip netns add inside
sudo ip link add veth-h type veth peer name veth-i
sudo ip link set veth-i netns inside
sudo ip addr add 10.50.0.1/24 dev veth-h
sudo ip link set veth-h up
sudo ip netns exec inside ip addr add 10.50.0.2/24 dev veth-i
sudo ip netns exec inside ip link set veth-i up
sudo ip netns exec inside ip link set lo up
sudo ip netns exec inside ip route add default via 10.50.0.1

# включаем форвардинг и SNAT
sudo sysctl -w net.ipv4.ip_forward=1
sudo iptables -t nat -A POSTROUTING -s 10.50.0.0/24 ! -o veth-h -j MASQUERADE

sudo ip netns exec inside curl -s --max-time 5 https://ifconfig.me
```

Если ответил твой публичный адрес — SNAT работает. Прибери:

```bash
sudo iptables -t nat -D POSTROUTING -s 10.50.0.0/24 ! -o veth-h -j MASQUERADE
sudo ip link del veth-h
sudo ip netns del inside
```

### Задача 2. «Сервис не отвечает» — диагностический скрипт

Запусти `python3 -m http.server 8080 &` и сделай так, чтобы извне он **не отвечал**. Затем по шагам найди причину:

1. Процесс жив? `ps` / `pgrep`.
2. Сокет слушается? `ss -tlnp | grep 8080`.
3. Слушает ли на нужном адресе? (`0.0.0.0` vs `127.0.0.1`).
4. Правило ufw разрешает? `ufw status | grep 8080`.
5. Маршрутизация на клиенте до тебя? `ip route get <client-ip>` с VM, `traceroute` с клиента.

Это типовой порядок «снизу вверх», его спрашивают на собесе.

### Задача 3. iptables → ufw → читать одно через другое

Открой 80/tcp через `ufw allow 80/tcp`. Затем найди соответствующее правило в `sudo iptables -S` и в `sudo nft list ruleset` (если используется nft-бэкенд). Покажи, какие цепочки задействованы. Закрой обратно `ufw delete allow 80/tcp`.

## Acceptance criteria

- [ ] `ip -br addr` показывает основной IP и `10.99.0.10/24` дополнительно.
- [ ] `ip route` имеет `default via …`.
- [ ] `sudo ufw status` — active, 22/tcp разрешён, всё прочее запрещено.
- [ ] `sudo iptables -S | grep ufw` — содержит цепочки `ufw-*`.
- [ ] (Расширенная) с `ip netns exec inside curl ifconfig.me` уходит через masquerade.
- [ ] Ты можешь устно объяснить: процесс → сокет → firewall → routing.

## Что обсудить на ревью

1. Чем bridge отличается от NAT-сети в libvirt? Когда выбираем что?
2. Почему `netplan try` безопаснее `apply`?
3. Что произойдёт, если включить ufw до того, как разрешил 22/tcp?
4. Где живёт conntrack-таблица и зачем она нужна для NAT?
5. Чем `ufw` хуже прямой работы с `nft`? (Подсказка: видимость, версионирование, сложные правила.)

## Грабли

| Симптом | Причина | Лечение |
|---------|---------|---------|
| `netplan apply` — `Permission denied` warning | права не `0600` | `chmod 0600 /etc/netplan/*.yaml` |
| ufw включил — связь пропала | enable раньше allow 22 | защититься через `at`-rollback (см. шаг 4) |
| `curl` извне не отвечает | сервис слушает 127.0.0.1 | bind на `0.0.0.0` или `::` |
| MASQUERADE «не работает» | забыл `sysctl net.ipv4.ip_forward=1` | включить и закрепить в `/etc/sysctl.d/` |
| Bridge без IP не пингуется | bridge должен быть `up` И иметь адрес | `ip link set br up; ip addr add ... dev br` |
