# Сценарий 01: ping не идёт — интерфейс DOWN

## Симптом
Адрес назначен, сосед настроен, а ping не проходит — «Network is unreachable» или
100% loss.
```bash
sudo ./broken/scenario-01/make-broken.sh
# vb1 поднят с адресом, но БЕЗ 'ip link set up':
# vb1   DOWN   ...
# ping bn1→bn2: FAIL
```

## Подсказки
1. Посмотри состояние интерфейса: `ip -br link` (UP или DOWN?).
2. Назначить адрес и поднять интерфейс — это одна команда или две?
3. Что показывает `ip route` в namespace, если интерфейс DOWN?

## Диагностика
`ip addr add` только назначает адрес, но НЕ поднимает интерфейс — он остаётся в
состоянии `DOWN`. Пока интерфейс не `UP`, ядро не активирует связанный с ним
маршрут (подсеть `10.88.0.0/24`), поэтому пакету некуда идти → «Network is
unreachable». Очень частая ошибка: назначили IP и забыли `ip link set <if> up`
(и так же легко забыть `lo up` внутри namespace).

## Решение
Поднять интерфейс (см. `solutions/01-link-up/fix.sh`):
```bash
sudo ./solutions/01-link-up/fix.sh
# ip link set vb1 up → ping bn1→bn2: OK
```

## Профилактика
- После `ip addr add` всегда `ip link set <if> up` (для ОБОИХ концов veth и для `lo`).
- Быстрая диагностика связности: `ip -br addr` и `ip -br link` показывают адреса и
  состояние UP/DOWN в одну строку на интерфейс.
- «Network is unreachable» почти всегда = нет активного маршрута → проверь, что
  интерфейс UP и есть адрес/route, а не сразу лезь в iptables.
