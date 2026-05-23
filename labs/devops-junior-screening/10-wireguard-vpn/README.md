# 10 · WireGuard VPN

> Тема из вакансии: «WireGuard / VPN» (как плюс).

## Цель и навыки

Поднять point-to-point WireGuard-туннель между **контрольной машиной (твой ноут / WSL)** и учебной VM. Понять модель «keys + endpoints + allowed_ips», научиться читать `wg show` и диагностировать «почему пинг не идёт».

После лабы ты:

- знаешь, что WG — это **stateless** UDP-протокол (`51820/udp`), без TLS, без TCP, без рукопожатий с ASN.1;
- понимаешь модель: у каждого peer есть приватный ключ + ты знаешь публичные ключи peers + список **AllowedIPs**, которые через них доступны;
- настраиваешь конфиг через `wg-quick` (systemd-friendly);
- объясняешь, почему `AllowedIPs` — это **и роутинг, и ACL** одновременно;
- умеешь сделать full-tunnel (весь трафик через VPN) vs split-tunnel (только подсеть);
- знаешь, как добавлять новых peers без рестарта сервера (`wg set`).

## Теоретический минимум

**WireGuard** в ядре Linux с 5.6 — встроенный модуль, никаких DKMS. Конфиг — `[Interface]` (твоя сторона) + один или несколько `[Peer]`.

```
[Interface]
PrivateKey = ...
Address    = 10.99.0.1/24
ListenPort = 51820

[Peer]
PublicKey  = ...
AllowedIPs = 10.99.0.2/32          # роутинг + cryptokey-ACL
Endpoint   = 1.2.3.4:51820          # необязательно (одна сторона может быть «динамической»)
PersistentKeepalive = 25            # пробить NAT
```

**Cryptokey routing.** WG не использует обычные iptables-ACL. Если пакет приходит с peer'а, и его source-IP **не в** `AllowedIPs` — пакет молча дропается. Если ты хочешь отправить пакет, и его destination-IP не в `AllowedIPs` ни одного peer'а — пакет не уйдёт через WG-интерфейс.

**`wg-quick` vs `wg`.** `wg` — низкоуровневая утилита («поставь этот ключ, добавь этого peer»). `wg-quick up wg0` берёт `/etc/wireguard/wg0.conf`, поднимает интерфейс, ставит адрес, прописывает маршруты, поднимает firewall-хуки. На прод — `systemctl enable wg-quick@wg0`.

## Базовая отработка

### Шаг 1. Установка на обе стороны

```bash
sudo apt-get install -y wireguard
sudo modprobe wireguard && lsmod | grep wireguard
wg --version
```

Сделай это и на VM (`ubuntu@44.x`), и на контрольной машине.

### Шаг 2. Сгенерировать ключи

На **VM** (сервер):

```bash
cd /etc/wireguard && sudo umask 077
sudo bash -c 'wg genkey | tee server.key | wg pubkey > server.pub'
sudo cat server.pub                # запишем это в client-конфиг
```

На **контрольной машине** (клиент):

```bash
sudo mkdir -p /etc/wireguard && sudo umask 077
sudo bash -c 'wg genkey | tee /etc/wireguard/client.key | wg pubkey > /etc/wireguard/client.pub'
sudo cat /etc/wireguard/client.pub
```

### Шаг 3. Конфиги

**Сервер (на VM), `/etc/wireguard/wg0.conf`:**

```ini
[Interface]
PrivateKey = <содержимое server.key>
Address    = 10.99.0.1/24
ListenPort = 51820
# простой NAT, чтобы клиент мог выйти в инет через VM (split-tunnel — необязательно)
PostUp   = iptables -t nat -A POSTROUTING -o ens5 -j MASQUERADE
PostDown = iptables -t nat -D POSTROUTING -o ens5 -j MASQUERADE

[Peer]
# Клиент
PublicKey  = <содержимое client.pub>
AllowedIPs = 10.99.0.2/32
```

> Уточни имя внешнего интерфейса: `ip -br link` — на EC2 это `ens5`. И **разрешите forwarding**: `echo 'net.ipv4.ip_forward=1' | sudo tee /etc/sysctl.d/99-wg.conf && sudo sysctl --system`.

**Клиент (контрольная машина), `/etc/wireguard/wg0.conf`:**

```ini
[Interface]
PrivateKey = <содержимое client.key>
Address    = 10.99.0.2/24

[Peer]
PublicKey            = <содержимое server.pub>
Endpoint             = 44.203.82.110:51820
AllowedIPs           = 10.99.0.0/24
PersistentKeepalive  = 25
```

### Шаг 4. Открыть UDP/51820

На VM:

```bash
sudo ufw allow 51820/udp comment 'wireguard'
```

**На AWS Security Group**: добавь правило `UDP 51820` from `0.0.0.0/0` (или твой IP). **Это самая частая причина «не работает»** — порт открыт в ufw, но AWS SG режет.

### Шаг 5. Поднять и проверить

На обеих сторонах:

```bash
sudo wg-quick up wg0
sudo wg show                    # latest handshake, transfer
ip -br addr show wg0
```

С контрольной машины:

```bash
ping -c 3 10.99.0.1
ssh -i ~/.ssh/vast ubuntu@10.99.0.1 'echo via wg ok; ip -br addr show wg0'
```

Если хендшейк есть, а ping не идёт — значит, conntrack/MASQUERADE/forwarding (см. шаг 3).

### Шаг 6. Persistence

```bash
# на обеих сторонах
sudo systemctl enable wg-quick@wg0
sudo systemctl status wg-quick@wg0
```

## Расширенная отработка

### Задача 1. Добавить второго клиента «без рестарта»

Сгенерируй второй клиентский ключ. Добавь его через CLI без правки конфига:

```bash
sudo wg set wg0 peer <NEW_PUB> allowed-ips 10.99.0.3/32
sudo wg show wg0
```

Сохрани изменения в конфиг:

```bash
sudo wg-quick save wg0          # перепишет /etc/wireguard/wg0.conf
```

### Задача 2. Full-tunnel (весь трафик через WG)

На клиенте поменяй `AllowedIPs = 0.0.0.0/0, ::/0`. После `wg-quick down/up wg0` — твой публичный IP станет IP'шником VM:

```bash
curl https://ifconfig.me        # должен ответить 44.203.82.110
```

> Это и есть «личный VPN». Возврат к split-tunnel — `AllowedIPs = 10.99.0.0/24`.

### Задача 3. Site-to-site (бонус)

Подними две VM и соедини их подсети (`10.10.0.0/24` ↔ `10.20.0.0/24`). На каждой стороне в `AllowedIPs` peer'а **противоположная** подсеть, на хостах внутри добавь маршрут до WG-шлюза. Это паттерн «филиал ↔ датацентр».

## Acceptance criteria

- [ ] `sudo wg show wg0` показывает `latest handshake` < 2 минут.
- [ ] `ping 10.99.0.1` идёт стабильно (latency сопоставим с публичным).
- [ ] `ssh ubuntu@10.99.0.1` работает через тоннель.
- [ ] `systemctl status wg-quick@wg0` — active (exited), `enable`d.
- [ ] (Расширенная) full-tunnel: `curl ifconfig.me` показывает IP VM.

## Что обсудить на ревью

1. Почему WG — UDP? Можно ли его через TCP? (Подсказка: формально нельзя, но есть `udp2raw`/`wstunnel` обёртки.)
2. Что такое **cryptokey routing**? Чем оно концептуально отличается от обычного firewall?
3. Зачем `PersistentKeepalive`? (Подсказка: NAT-таблицы у CGN-роутеров истекают.)
4. Чем WG лучше IPsec/OpenVPN на проде? Чем хуже? (Подсказка: meta-data, dynamic peers, audit-trail.)
5. Как ротировать ключи без даунтайма? (Подсказка: добавить **новый** peer, переключить клиента, удалить старый.)

## Как погасить

```bash
sudo wg-quick down wg0
sudo systemctl disable wg-quick@wg0
sudo rm /etc/wireguard/{wg0.conf,server.key,server.pub}   # ключи!
# не забудь убрать правило 51820/udp из SG, чтобы не светилось наружу
```

## Грабли

| Симптом | Причина | Лечение |
|---------|---------|---------|
| `wg show` пустой handshake | SG/файрвол режет UDP/51820 | AWS SG → разрешить UDP/51820 |
| Handshake есть, ping не идёт | forwarding или MASQUERADE | `sysctl net.ipv4.ip_forward=1`, проверь `iptables -t nat -S` |
| Клиент не может выйти в инет в full-tunnel | DNS остался свой, маршрут до 1.1.1.1 пошёл в WG, но MASQUERADE на VM не настроен | проверь `iptables -t nat -nL POSTROUTING` |
| `RTNETLINK answers: Operation not permitted` | работа без sudo / wg-quick без root | sudo |
| Туннель «дрожит» (handshake каждые 2-3 минуты) | NAT-роутер истекает | `PersistentKeepalive = 25` обеим сторонам |
| Конфиг утечь в git | сохранил `wg0.conf` с приватным ключом | `.gitignore /etc/wireguard/`, ключи в Vault |
