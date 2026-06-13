# Лабораторная работа 09: сеть контейнеров — veth, bridge, NAT

## Оглавление
<!-- TOC -->
- [Предварительные требования](#-)
- [Стартовая проверка](#-)
- [Часть 1: veth pair — прямая связь двух namespace](#-1-veth-pair-----namespace)
  - [Теория для изучения перед частью](#----)
  - [1.1 Соединить alpha ↔ beta](#11--alpha--beta)
- [Часть 2: bridge — несколько контейнеров в одной сети](#-2-bridge------)
  - [Теория для изучения перед частью](#----)
  - [2.1 Подключить alpha/beta/gamma к мосту](#21--alphabetagamma--)
- [Часть 3: NAT — выход во внешний мир](#-3-nat-----)
  - [Теория для изучения перед частью](#----)
  - [3.1 Дать alpha выход в интернет](#31--alpha---)
- [Часть 4: Troubleshooting](#-4-troubleshooting)
  - [Теория: диагностика по симптому](#---)
  - [Инцидент 1: ping не идёт — интерфейс DOWN](#-1-ping-----down)
- [Проверка модуля](#-)
- [Финальная карта ресурсов модуля](#---)
- [Теоретические вопросы (итоговые)](#--)
- [Практические задания (отработка)](#--)
- [Шпаргалка](#)
- [Чему вы научились](#--)
- [Уборка](#)
<!-- /TOC -->


> ⏱ время ~45 мин · сложность 4/5 · пререквизиты: 02-namespaces (net-ns), базовый TCP/IP

Цель: дать «пустому» сетевому namespace (этап 02) связь — сначала с соседом, потом
со всеми через мост, потом с внешним миром. Три кирпича: **veth pair** (виртуальный
патч-корд из двух интерфейсов), **bridge** (программный L2-коммутатор) и **NAT**
(`MASQUERADE`, чтобы приватные адреса ходили наружу с IP хоста). Это ровно сеть
`bridge` у Docker (мост `docker0`, подсеть `172.17.0.0/16`).

> Развитие `02-namespaces` (там net-ns был пустой — только `lo`, и тот DOWN).
> Выводы сняты на WSL2 (ядро 6.6); veth/bridge/NAT работают и на реальном хосте.
> Важный нюанс — `br_netfilter` (Часть 2): bridged-трафик проходит через iptables
> `FORWARD` (policy DROP на Docker/WSL2-хостах), поэтому мосту нужен `FORWARD ACCEPT`.

---

## Предварительные требования

```bash
sudo ./00-setup/check.sh            # ip (iproute2), iptables
command -v ip iptables >/dev/null && echo "ip + iptables на месте"
```

---

## Стартовая проверка

```bash
ip netns list 2>/dev/null; echo "—"   # список netns (обычно пуст в начале)
```

---

## Часть 1: veth pair — прямая связь двух namespace

### Теория для изучения перед частью

- **veth pair** — два связанных виртуальных интерфейса: что «вошло» в один, «вышло»
  из другого. Кладём один конец в один net-ns, второй — в другой; назначаем IP из
  одной подсети, поднимаем (`ip link set ... up`) — и они пингуются напрямую.
- Это L2-«патч-корд» на двоих. Для связи МНОГИХ нужен мост (Часть 2).

---

### 1.1 Соединить alpha ↔ beta

```bash
ip netns add alpha; ip netns add beta
ip link add veth-a type veth peer name veth-b
ip link set veth-a netns alpha; ip link set veth-b netns beta
ip netns exec alpha sh -c 'ip addr add 10.55.0.1/24 dev veth-a; ip link set veth-a up; ip link set lo up'
ip netns exec beta  sh -c 'ip addr add 10.55.0.2/24 dev veth-b; ip link set veth-b up; ip link set lo up'

ip netns exec alpha ping -c2 -W1 10.55.0.2
# 64 bytes from 10.55.0.2: icmp_seq=1 ttl=64 time=0.082 ms
# 2 packets transmitted, 2 received, 0% packet loss
```

**Контрольные вопросы:**
1. Что такое veth pair и как ведут себя его два конца?
2. Почему оба интерфейса нужно `ip link set up` (и зачем `lo up`)?
3. Чем veth отличается от bridge?

---

## Часть 2: bridge — несколько контейнеров в одной сети

### Теория для изучения перед частью

- **bridge** — программный L2-switch. Каждый «контейнер» подключается к нему
  veth-парой: один конец в net-ns, второй (`br-*`) — `master` моста. Мосту дают IP
  (`10.55.0.254`) — это default gateway для контейнеров.
- **Нюанс `br_netfilter`:** если загружен модуль `br_netfilter` и
  `net.bridge.bridge-nf-call-iptables=1` (так на хостах с Docker, и на WSL2),
  пакеты МЕЖДУ портами моста проходят через iptables `FORWARD`. А там policy
  **DROP** → ping контейнер↔контейнер молча не идёт, пока не добавишь
  `iptables -A FORWARD -i <br> -j ACCEPT` (это и делает Docker).

---

### 2.1 Подключить alpha/beta/gamma к мосту

```bash
ip netns del alpha; ip netns del beta            # пересоберём через мост
ip link add lab-br type bridge; ip link set lab-br up
ip addr add 10.55.0.254/24 dev lab-br
# нужно для br_netfilter-хостов (Docker/WSL2): пропустить bridged-трафик
iptables -A FORWARD -i lab-br -j ACCEPT; iptables -A FORWARD -o lab-br -j ACCEPT

for ns in alpha beta gamma; do
  ip netns add "$ns"
  ip link add "veth-$ns" type veth peer name "br-$ns"
  ip link set "br-$ns" master lab-br; ip link set "br-$ns" up
  ip link set "veth-$ns" netns "$ns"
done
i=1; for ns in alpha beta gamma; do
  ip netns exec "$ns" sh -c "ip addr add 10.55.0.$i/24 dev veth-$ns; ip link set veth-$ns up; ip link set lo up; ip route add default via 10.55.0.254"
  i=$((i+1))
done

ip netns exec alpha ping -c2 -W1 10.55.0.3        # alpha → gamma через мост
# 2 packets transmitted, 2 received, 0% packet loss
```

**Контрольные вопросы:**
1. Зачем мосту IP-адрес и чем он служит для контейнеров?
2. Почему контейнер↔контейнер через мост может «не пинговаться» на хосте с Docker?
3. Что делает `ip link set br-X master lab-br`?

---

## Часть 3: NAT — выход во внешний мир

### Теория для изучения перед частью

- У контейнеров приватные адреса (`10.55.0.0/24`) — в интернете нероутируемые.
  Чтобы их пакеты уходили наружу с адресом хоста, нужен **SNAT/MASQUERADE** на
  исходящем интерфейсе: `iptables -t nat -A POSTROUTING -s 10.55.0.0/24 -j
  MASQUERADE`. MASQUERADE = SNAT с автоподстановкой IP исходящего интерфейса.
- Плюс Linux должен **роутить** между интерфейсами: `net.ipv4.ip_forward=1` (по
  умолчанию хост не роутер).

---

### 3.1 Дать alpha выход в интернет

```bash
sysctl -w net.ipv4.ip_forward=1
EXT_IF=$(ip -o route get 1.1.1.1 | grep -o 'dev [^ ]*' | awk '{print $2}')   # внешний интерфейс
iptables -t nat -A POSTROUTING -s 10.55.0.0/24 -j MASQUERADE

ip netns exec alpha ping -c2 -W2 1.1.1.1
# 64 bytes from 1.1.1.1: icmp_seq=1 ttl=... time=4.0 ms
# 2 packets transmitted, 2 received, 0% packet loss      <- наружу через NAT
```

**Контрольные вопросы:**
1. Что такое MASQUERADE и чем отличается от явного SNAT?
2. Зачем `net.ipv4.ip_forward=1`?
3. Что соответствует этому в Docker (мост + правило в nat-таблице)?

---

## Часть 4: Troubleshooting

### Теория: диагностика по симптому

```
Симптом
├─ ping не идёт, «Network is unreachable» ──────► интерфейс DOWN (забыт ip link set
│     up) или нет адреса/маршрута. ip -br addr; ip link set <if> up (Сценарий 01)
├─ контейнер↔контейнер через мост молчит ───────► br_netfilter + FORWARD policy DROP.
│     iptables -A FORWARD -i <br> -j ACCEPT (или bridge-nf-call-iptables=0)
├─ внутри пинг ok, наружу (1.1.1.1) нет ─────────► нет MASQUERADE или ip_forward=0,
│     либо у самого хоста нет интернета. Проверь nat-POSTROUTING и sysctl
└─ default route отсутствует в netns ────────────► ip route add default via <gw>;
      без него контейнер не выйдет за пределы своей подсети
```

### Инцидент 1: ping не идёт — интерфейс DOWN
Разобран в `broken/scenario-01/` (veth поднят с адресом, но без `ip link set up`).
Воспроизвести и починить:
```bash
sudo ./broken/scenario-01/make-broken.sh        # veth DOWN → ping FAIL
sudo ./solutions/01-link-up/fix.sh                # ip link set up → ping OK
```

---

## Проверка модуля

```bash
sudo ./scripts/qa/run-module.sh 09-networking
# --- module: 09-networking ---
# prepare...
# [OK] сеть собрана: мост lab-br-v + nv1(.1)/nv2(.2), FORWARD ACCEPT
# verify...
# [OK] L2 через мост: nv1 → nv2
# [OK] nv1 → шлюз моста (10.77.0.254)
# [OK] NAT outbound: nv1 → 1.1.1.1 (через MASQUERADE)   (или [WARN] если нет интернета)
# [OK] module 09-networking verified
```

NAT-проверка best-effort: на хосте без интернета печатается `[WARN]` и прогон не
падает. Полное демо (3 части) — `sudo ./run.sh`.

---

## Финальная карта ресурсов модуля

| Ресурс | Что это | Демонстрирует |
|--------|---------|---------------|
| veth pair | два связанных интерфейса | патч-корд контейнер↔хост |
| `type bridge` + `master` | L2-switch и порты | мост `docker0` |
| IP на мосту | L3-шлюз | default gateway контейнера |
| `iptables FORWARD ACCEPT` | пропуск bridged-трафика | обход br_netfilter DROP |
| `MASQUERADE` + `ip_forward` | NAT + роутинг | выход контейнера в интернет |

---

## Теоретические вопросы (итоговые)
1. Чем veth отличается от bridge и как они сочетаются?
2. Зачем мосту IP и что будет без него?
3. Почему контейнер↔контейнер через мост может молчать (br_netfilter)?
4. Что такое MASQUERADE и зачем `ip_forward=1`?
5. Как `--network host` у Docker меняет картину (нет своего net-ns)?

> Разбор ответов — в `ANSWERS.md`.

---

## Практические задания (отработка)

См. `tasks/`:
1. **`tasks/01-veth-pair.md`** — соединить два netns veth-парой, пинг между ними.
2. **`tasks/02-bridge.md`** — мост + несколько netns, пинг через мост (с FORWARD ACCEPT).
3. **`tasks/03-nat.md`** — MASQUERADE + ip_forward, пинг наружу.

Дополнительно:
4. Запусти HTTP-сервер в netns и пробрось порт с хоста через `iptables -t nat -A PREROUTING ... DNAT`.
5. Сравни `tcpdump -i lab-br` при пинге контейнер↔контейнер и контейнер→внешний.

---

## Шпаргалка

```bash
# === veth pair между двумя netns ===
ip netns add c1; ip netns add c2
ip link add v1 type veth peer name v2
ip link set v1 netns c1; ip link set v2 netns c2
ip netns exec c1 sh -c 'ip addr add 10.0.0.1/24 dev v1; ip link set v1 up; ip link set lo up'

# === bridge ===
ip link add br0 type bridge; ip link set br0 up; ip addr add 10.0.0.254/24 dev br0
ip link set <br-end> master br0; ip link set <br-end> up
iptables -A FORWARD -i br0 -j ACCEPT          # для br_netfilter-хостов (Docker/WSL2)

# === NAT outbound ===
sysctl -w net.ipv4.ip_forward=1
iptables -t nat -A POSTROUTING -s 10.0.0.0/24 -j MASQUERADE

# === диагностика ===
ip -br addr; ip -br link        # адреса и состояние (UP/DOWN) кратко
ip netns exec <ns> ip route     # есть ли default route
iptables -L FORWARD -n -v       # policy и счётчики
```

---

## Чему вы научились
- Соединять net-namespace veth-парой и мостом, давать контейнерам связь L2/L3.
- Понимать роль IP на мосту (default gateway) и нюанс `br_netfilter`/FORWARD.
- Выпускать контейнеры наружу через `MASQUERADE` + `ip_forward`.
- Сопоставлять это с сетью `bridge` Docker (`docker0`, MASQUERADE-правило).

---

## Уборка

```bash
sudo ./verify/cleanup.sh
# [OK] cleanup 09-networking
```

> Дальше — `10-rootfs-and-nspawn`: собрать настоящий rootfs (`debootstrap`) и
> запустить его через `systemd-nspawn` — мост к `FROM alpine` / `docker run`.
> (Host-only: на WSL2 нет `systemd-nspawn`/`debootstrap`.)
