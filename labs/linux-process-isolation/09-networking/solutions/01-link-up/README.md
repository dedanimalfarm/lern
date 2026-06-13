# Решение scenario-01: поднять интерфейс (`ip link set up`)

`ip addr add` только назначает адрес — интерфейс остаётся `DOWN`, и связанный
маршрут не активен. Нужно поднять интерфейс:

```bash
ip addr add 10.88.0.1/24 dev vb1
ip link set vb1 up          # ← обязательно
ip link set lo up           # внутри netns тоже
```

```bash
sudo 09-networking/broken/scenario-01/make-broken.sh    # vb1 DOWN → ping FAIL
sudo 09-networking/solutions/01-link-up/fix.sh            # vb1 up → ping OK
```

Проверяй состояние одной командой: `ip -br link` (колонка UP/DOWN). «Network is
unreachable» почти всегда = нет активного маршрута → сначала проверь, что интерфейс
UP и есть адрес, и только потом — iptables.
