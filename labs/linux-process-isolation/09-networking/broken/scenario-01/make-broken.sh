#!/usr/bin/env bash
# Воспроизводит инцидент scenario-01: veth поднят с адресом, но БЕЗ 'ip link set up'
# → интерфейс DOWN, маршрут не активен, ping не идёт.
set -uo pipefail
[[ "${EUID:-$(id -u)}" -eq 0 ]] || { echo "нужен root: sudo $0"; exit 1; }
command -v ip >/dev/null || { echo "нет ip (iproute2)"; exit 1; }

clean(){ ip netns del bn1 2>/dev/null || true; ip netns del bn2 2>/dev/null || true; }
clean
ip netns add bn1; ip netns add bn2
ip link add vb1 type veth peer name vb2
ip link set vb1 netns bn1; ip link set vb2 netns bn2
# bn1: назначаем адрес, но НЕ поднимаем интерфейс (БАГ)
ip netns exec bn1 ip addr add 10.88.0.1/24 dev vb1
ip netns exec bn2 sh -c 'ip addr add 10.88.0.2/24 dev vb2; ip link set vb2 up; ip link set lo up'

echo "состояние vb1 в bn1 (БАГ — DOWN):"
ip netns exec bn1 ip -br link show vb1
echo -n "ping bn1->bn2: "
ip netns exec bn1 ping -c1 -W1 10.88.0.2 >/dev/null 2>&1 && echo OK || echo "FAIL (интерфейс DOWN → маршрут не активен)"

clean
echo "разбор: broken/scenario-01/README.md · фикс: solutions/01-link-up/fix.sh"
