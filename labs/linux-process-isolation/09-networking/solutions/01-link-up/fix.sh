#!/usr/bin/env bash
# Чинит инцидент scenario-01: поднимаем интерфейс (ip link set up) — маршрут
# активируется, ping проходит.
set -uo pipefail
[[ "${EUID:-$(id -u)}" -eq 0 ]] || { echo "нужен root: sudo $0"; exit 1; }
command -v ip >/dev/null || { echo "нет ip (iproute2)"; exit 1; }

clean(){ ip netns del bn1 2>/dev/null || true; ip netns del bn2 2>/dev/null || true; }
clean
ip netns add bn1; ip netns add bn2
ip link add vb1 type veth peer name vb2
ip link set vb1 netns bn1; ip link set vb2 netns bn2
# фикс: назначить адрес И поднять интерфейс
ip netns exec bn1 sh -c 'ip addr add 10.88.0.1/24 dev vb1; ip link set vb1 up; ip link set lo up'
ip netns exec bn2 sh -c 'ip addr add 10.88.0.2/24 dev vb2; ip link set vb2 up; ip link set lo up'

echo "состояние vb1 в bn1 (UP):"
ip netns exec bn1 ip -br link show vb1
echo -n "ping bn1->bn2: "
ip netns exec bn1 ping -c1 -W1 10.88.0.2 >/dev/null 2>&1 && echo OK || echo FAIL

clean
