# 10 · WireGuard VPN

> Тема из вакансии: «WireGuard / VPN» (как плюс).

**⏱ Время на выполнение:** ~45-60 минут
**Уровень сложности:** Средний (Intermediate)

## Оглавление
- [Цель и навыки](#цель-и-навыки)
- [Теоретический минимум](#теоретический-минимум)
- [Базовая отработка](#базовая-отработка)
  - [Шаг 1. Установка на обе стороны](#шаг-1-установка-на-обе-стороны)
  - [Шаг 2. Сгенерировать ключи](#шаг-2-сгенерировать-ключи)
  - [Шаг 3. Конфиги](#шаг-3-конфиги)
  - [Шаг 4. Открыть UDP/51820](#шаг-4-открыть-udp51820)
  - [Шаг 5. Поднять и проверить](#шаг-5-поднять-и-проверить)
  - [Шаг 6. Persistence](#шаг-6-persistence)
- [Расширенная отработка](#расширенная-отработка)
- [Проверка модуля](#проверка-модуля)
- [Контрольные вопросы](#контрольные-вопросы)
- [Troubleshooting — частые проблемы](#troubleshooting--частые-проблемы)
- [Уборка](#уборка)

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

```ini
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

## Проверка модуля

Убедиться, что лаба выполнена успешно, поможет скрипт автоматической проверки. Запустите его на той машине, где настраивали WireGuard:

```bash
./verify.sh
```

Критерии успеха:
- Интерфейс `wg0` поднят.
- Конфигурация сохранена в `/etc/wireguard/wg0.conf`.
- Systemd-сервис `wg-quick@wg0` включён.
- Пинг до адреса `10.99.0.1` или `10.99.0.2` проходит (в зависимости от стороны).
- `wg show` отображает наличие настроенного peer-а.

## Контрольные вопросы

1. Почему WireGuard работает по протоколу UDP? Можно ли его заставить работать через TCP и в каких ситуациях это может потребоваться?
2. Что такое концепция **cryptokey routing**? Чем оно концептуально отличается от обычного firewall и маршрутизации на основе IP-адресов?
3. Какую проблему решает параметр `PersistentKeepalive = 25`? Что произойдет, если его убрать у клиента, находящегося за обычным домашним NAT-роутером?
4. Чем WireGuard принципиально отличается от IPsec или OpenVPN в контексте использования в production? Назовите 2-3 плюса и минуса.
5. Как правильно ротировать ключи в WireGuard без даунтайма для клиентов? (Опишите пошаговый процесс).

## Troubleshooting — частые проблемы

| Симптом | Возможная причина | Диагностика / Решение |
|---------|-------------------|-----------------------|
| `wg show` пустой, нет поля `latest handshake` | SG/файрвол режет UDP/51820 | Проверить Security Groups в AWS/Cloud: разрешить UDP/51820. Проверить `sudo ufw status`. |
| Handshake есть, пинг не идёт | Не работает forwarding или MASQUERADE | Проверить `sysctl net.ipv4.ip_forward` (должна быть 1). Проверить `sudo iptables -t nat -S` (должен быть MASQUERADE для WG подсети). |
| Клиент не может выйти в интернет в full-tunnel (AllowedIPs = 0.0.0.0/0) | DNS недоступен через туннель или трафик не транслируется (NAT) на сервере | Добавить `DNS = 1.1.1.1` в клиентский конфиг. Проверить `iptables -t nat -L POSTROUTING -n -v` на сервере. |
| `RTNETLINK answers: Operation not permitted` | Недостаточно прав | Использовать `sudo wg-quick up wg0` |
| Туннель «дрожит», связь пропадает через несколько минут бездействия | NAT-таблицы на роутере устарели и закрыли сессию | Добавить `PersistentKeepalive = 25` в секцию `[Peer]` клиента (и/или сервера, если у клиента динамический IP). |
| Конфигурация случайно залита в git-репозиторий | Сохранен файл `wg0.conf` с приватным ключом | Немедленно перегенерировать ключи! Добавить `/etc/wireguard/` в `.gitignore` или хранить ключи во внешнем секретном хранилище (Vault). |
| Ошибка разрешения DNS имени Endpoint (`Name or service not known`) | Проблемы с локальным резолвером до поднятия туннеля | Если `Endpoint` указан как доменное имя, WireGuard резолвит его при старте. Если DNS падает при старте WG, туннель не поднимется. Заменить на IP. |

## Уборка

Чтобы вернуть систему в исходное состояние и удалить все созданные в рамках лабы ресурсы, запустите скрипт очистки:

```bash
./cleanup.sh
```

Вручную то же самое можно сделать так:
```bash
sudo wg-quick down wg0 || true
sudo systemctl disable wg-quick@wg0 || true
sudo rm -rf /etc/wireguard/wg0.conf /etc/wireguard/server.key /etc/wireguard/server.pub /etc/wireguard/client.key /etc/wireguard/client.pub
# Не забудьте удалить правило 51820/udp из AWS SG и ufw!
sudo ufw delete allow 51820/udp comment 'wireguard' || true
sudo rm -f /etc/sysctl.d/99-wg.conf
sudo sysctl --system
```
